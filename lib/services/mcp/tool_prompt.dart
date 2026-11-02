import 'dart:convert';

import '../../controllers/mcp_controller.dart';
import 'mcp_protocol.dart';

/// Function Calling 支持：工具定义 → system prompt 注入，
/// 以及模型输出中 ```tool 代码块的解析（文本级 function calling，
/// 不依赖 llama.cpp 原生 tools 参数，所有 chatml 模型可用）。
///
/// 针对小参数本地模型（0.5B~4B）做了重点容错：
/// - 提示词带 one-shot 示例与硬性规则，降低格式跑偏概率
/// - 解析器容忍尾逗号 / 单引号 / 裸键 / Python 字面量 / 全角符号
/// - 接受 ```json / ```tool_call 等别名代码块与未闭合代码块
/// - [parseDetailed] 返回可读错误，供上层把矫正信息回喂模型重试
class ToolPrompt {
  ToolPrompt._();

  /// 把工具列表转为注入 system prompt 的指令文本。
  ///
  /// [extraToolLines]：内置工具（如 ask_user_question）的描述行，
  /// 与 MCP / DSH 工具并列展示。
  static String buildToolsPrompt(
    List<({McpServerEntry server, McpTool tool})> tools, {
    List<String> extraToolLines = const <String>[],
  }) {
    if (tools.isEmpty && extraToolLines.isEmpty) return '';
    final buffer = StringBuffer()
      ..writeln('你可以使用以下工具完成任务。')
      ..writeln(
        '需要调用工具时，输出一个如下格式的代码块（一次只调用一个工具），'
        '块内是严格合法的 JSON：',
      )
      ..writeln('```tool')
      ..writeln('{"name": "get_weather", "arguments": {"city": "北京"}}')
      ..writeln('```')
      ..writeln()
      ..writeln('硬性规则：')
      ..writeln('1. 只能调用下面列出的工具，禁止编造工具名。')
      ..writeln(
        '2. JSON 必须合法：键和字符串值都用双引号，'
        '不要尾逗号、注释、单引号或多余文字。',
      )
      ..writeln('3. 参数名和类型必须与 JSON Schema 一致，必填参数不能缺。')
      ..writeln('4. 不需要工具时，直接用自然语言回答，不要输出 ```tool 代码块。')
      ..writeln(
        '5. 收到【工具执行结果】后基于结果回答；'
        '结果报错时修正参数后可重试同一工具。',
      )
      ..writeln()
      ..writeln('可用工具：');
    for (final line in extraToolLines) {
      buffer.writeln('- $line');
    }
    for (final item in tools) {
      buffer.writeln('- ${item.tool.name}：${item.tool.description}');
      final schema = jsonEncode(item.tool.inputSchema);
      buffer.writeln('  参数 JSON Schema：$schema');
    }
    return buffer.toString();
  }
}

/// 一次解析出的工具调用
class ToolCall {
  const ToolCall({required this.name, required this.arguments});

  final String name;
  final Map<String, dynamic> arguments;
}

/// 解析结果：成功时的调用列表 + 失败时的可读错误（供矫正回喂）
class ToolParseResult {
  const ToolParseResult({required this.calls, this.error});

  final List<ToolCall> calls;

  /// 模型试图调用工具但格式不合法时的错误描述；null 表示没有调用意图
  final String? error;

  bool get hasAttempt => error != null;
}

/// 从模型输出中解析工具调用代码块（宽容模式）
class ToolCallParser {
  ToolCallParser._();

  /// 接受的代码块语言标记（```tool 及常见变体）
  static const Set<String> _fenceLangs = <String>{
    'tool',
    'tool_call',
    'toolcall',
    'function_call',
    'functioncall',
    'json',
    'jsonc',
    'json5',
    'jsonl',
  };

  /// 未闭合代码块也算调用意图（小模型经常忘了写结尾 ```）
  static final RegExp _fencePattern = RegExp(
    r'```[ \t]*([\w-]*)[ \t]*\r?\n(.*?)(?:```|$)',
    dotAll: true,
  );

  static final RegExp _bareJsonPattern = RegExp(r'\{[\s\S]*\}');

  /// 便捷入口：只取调用列表
  static List<ToolCall> parse(String text) => parseDetailed(text).calls;

  /// 完整解析：调用列表 + 失败原因（矫正回喂用）
  static ToolParseResult parseDetailed(String text) {
    final calls = <ToolCall>[];
    var attempted = false;
    String? firstError;

    // ---------- 第一层：围栏代码块 ----------
    for (final match in _fencePattern.allMatches(text)) {
      final lang = (match.group(1) ?? '').toLowerCase();
      final body = (match.group(2) ?? '').trim();
      if (body.isEmpty) continue;

      final isToolFence = lang.isEmpty || _fenceLangs.contains(lang);
      if (!isToolFence) continue;

      final decoded = lenientJsonDecode(body);
      final call = decoded == null ? null : _toToolCall(decoded);
      if (call != null) {
        attempted = true;
        calls.add(call);
      } else {
        // lang 为空的围栏（普通代码示例）不当作调用意图；
        // 明确的 tool/json 围栏解析失败则记为一次错误尝试
        if (lang.isNotEmpty) {
          attempted = true;
          firstError ??= '代码块内容不是合法 JSON：${_snippet(body)}';
        }
      }
    }
    if (calls.isNotEmpty) return ToolParseResult(calls: calls);

    // ---------- 第二层：裸 JSON 对象（模型忘了写围栏） ----------
    final bare = _bareJsonPattern.firstMatch(text);
    if (bare != null) {
      final decoded = lenientJsonDecode(bare.group(0)!);
      final call = decoded == null ? null : _toToolCall(decoded);
      if (call != null) return ToolParseResult(calls: [call]);
      if (text.contains('"name"') || text.contains("'name'")) {
        attempted = true;
        firstError ??= '输出含 JSON 对象但缺少合法的 name/arguments 字段';
      }
    }

    return ToolParseResult(
      calls: const <ToolCall>[],
      error: attempted ? (firstError ?? '工具调用格式不合法') : null,
    );
  }

  /// 解码后的 Map → ToolCall（含字段别名兼容）
  static ToolCall? _toToolCall(Map<String, dynamic> map) {
    // name 字段别名：name / tool / tool_name / function / toolName
    dynamic name =
        map['name'] ??
        map['tool'] ??
        map['tool_name'] ??
        map['toolName'] ??
        (map['function'] is Map ? (map['function'] as Map)['name'] : null);
    if (name is! String || name.trim().isEmpty) return null;

    // arguments 字段别名：arguments / args / parameters / params
    var args =
        map['arguments'] ?? map['args'] ?? map['parameters'] ?? map['params'];
    if (args == null && map['function'] is Map) {
      args = (map['function'] as Map)['arguments'];
    }
    if (args is String && args.trim().isNotEmpty) {
      // 部分模型把 arguments 输出成 JSON 字符串，兼容二次解码
      final inner = lenientJsonDecode(args);
      args = inner ?? args;
    }
    return ToolCall(
      name: name.trim(),
      arguments: args is Map
          ? args.cast<String, dynamic>()
          : <String, dynamic>{},
    );
  }

  /// 宽松 JSON 解码：标准解码失败后逐级修复再试。
  ///
  /// 覆盖小模型最常见的格式错误：
  /// 全角符号、尾逗号、单引号、裸键名、Python 字面量（True/False/None）。
  static dynamic lenientJsonDecode(String input) {
    // 1. 标准 JSON
    try {
      return jsonDecode(input);
    } catch (_) {}

    var s = input.trim();
    // 2. 去掉包裹的说明文字：截取首个 { 到末个 }
    final start = s.indexOf('{');
    final end = s.lastIndexOf('}');
    if (start >= 0 && end > start) {
      final sliced = s.substring(start, end + 1);
      final direct = _repairAndDecode(sliced);
      if (direct != null) return direct;
    }
    return _repairAndDecode(s);
  }

  static dynamic _repairAndDecode(String s) {
    var repaired = s
        // 全角标点 → 半角（小模型中文语境常见）
        .replaceAll('｛', '{')
        .replaceAll('｝', '}')
        .replaceAll('，', ',')
        .replaceAll('：', ':')
        .replaceAll('＂', '"')
        .replaceAll('「', '"')
        .replaceAll('」', '"')
        // Python 字面量
        .replaceAllMapped(
          RegExp(r'\b(True|False|None)\b'),
          (m) => switch (m.group(1)) {
            'True' => 'true',
            'False' => 'false',
            _ => 'null',
          },
        )
        // 尾逗号：}, 或 ] 前的逗号
        .replaceAllMapped(RegExp(r',\s*([}\]])'), (m) => m.group(1)!)
        // 单引号字符串 → 双引号（不含转义与嵌套的简化处理）
        .replaceAllMapped(RegExp(r"'([^'\\]*)'"), (m) => '"${m.group(1)}"')
        // 裸键名：{ 或 , 后的无引号键
        .replaceAllMapped(
          RegExp(r'([{,]\s*)([A-Za-z_][A-Za-z0-9_\-]*)\s*:'),
          (m) => '${m.group(1)}"${m.group(2)}":',
        );
    try {
      return jsonDecode(repaired);
    } catch (_) {
      return null;
    }
  }

  static String _snippet(String s) {
    final t = s.replaceAll('\n', ' ');
    return t.length > 60 ? '${t.substring(0, 60)}…' : t;
  }

  /// 严格 tool 围栏（气泡摘要清理用，不吞普通代码块）
  static final RegExp _strictToolFence = RegExp(
    r'```[ \t]*(?:tool|tool_call|toolcall|function_call|functioncall)[ \t]*'
    r'\r?\n.*?(?:```|$)',
    dotAll: true,
  );

  /// 把工具调用原文替换为可读摘要（对话气泡展示用）：
  /// 优先清理 tool 围栏；裸 JSON 调用则把该 JSON 对象替换为摘要
  static String stripToolBlocks(String text, List<ToolCall> calls) {
    var result = text;
    for (final call in calls) {
      final summary = '🔧 调用工具 ${call.name}';
      if (_strictToolFence.hasMatch(result)) {
        result = result.replaceFirst(_strictToolFence, summary);
        continue;
      }
      final bare = _bareJsonPattern.firstMatch(result);
      if (bare != null && result.startsWith(bare.group(0)!.trim())) {
        result = result.replaceFirst(_bareJsonPattern, summary);
      } else {
        result = '$summary\n$result';
      }
    }
    return result;
  }
}
