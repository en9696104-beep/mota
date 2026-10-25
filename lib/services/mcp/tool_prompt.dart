import 'dart:convert';

import '../../controllers/mcp_controller.dart';
import 'mcp_protocol.dart';

/// Function Calling 支持：工具定义 → system prompt 注入，
/// 以及模型输出中 ```tool 代码块的解析（文本级 function calling，
/// 不依赖 llama.cpp 原生 tools 参数，所有 chatml 模型可用）
class ToolPrompt {
  ToolPrompt._();

  /// 把工具列表转为注入 system prompt 的指令文本
  static String buildToolsPrompt(List<({McpServerEntry server, McpTool tool})> tools) {
    if (tools.isEmpty) return '';
    final buffer = StringBuffer()
      ..writeln('你可以使用以下工具完成任务。')
      ..writeln('需要调用工具时，必须且只能输出一个如下格式的代码块，'
          '不要输出任何其他文字：')
      ..writeln('```tool')
      ..writeln('{"name": "工具名", "arguments": {"参数名": "参数值"}}')
      ..writeln('```')
      ..writeln('收到工具结果后，基于结果用自然语言回答用户。'
          '不需要工具时直接正常回答。')
      ..writeln()
      ..writeln('可用工具：');
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

/// 从模型输出中解析 ```tool 代码块
class ToolCallParser {
  ToolCallParser._();

  static final RegExp _blockPattern = RegExp(
    r'```tool\s*\n(.*?)```',
    dotAll: true,
  );

  /// 提取全部工具调用；代码块内容不是合法 JSON 时跳过该块
  static List<ToolCall> parse(String text) {
    final calls = <ToolCall>[];
    for (final match in _blockPattern.allMatches(text)) {
      try {
        final decoded = jsonDecode(match.group(1)!.trim());
        if (decoded is! Map) continue;
        final name = decoded['name'];
        if (name is! String || name.isEmpty) continue;
        var args = decoded['arguments'];
        if (args is String) {
          // 部分模型会把 arguments 输出成 JSON 字符串，兼容解析
          try {
            args = jsonDecode(args);
          } catch (_) {}
        }
        calls.add(
          ToolCall(
            name: name,
            arguments: args is Map ? args.cast<String, dynamic>() : <String, dynamic>{},
          ),
        );
      } catch (_) {
        // 非法 JSON 块：忽略（模型可能还在流式输出中）
      }
    }
    return calls;
  }

  /// 把 ```tool 代码块替换为可读的调用摘要（对话气泡展示用）
  static String stripToolBlocks(String text, List<ToolCall> calls) {
    var result = text;
    for (final call in calls) {
      result = result.replaceFirst(
        _blockPattern,
        '🔧 调用工具 ${call.name}',
      );
    }
    return result;
  }
}
