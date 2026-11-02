import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter_js/flutter_js.dart';

import 'dsh_models.dart';

/// DSH 插件 QuickJS 运行时。
///
/// 每次发现/调用在独立 isolate 中新建 QuickJS 实例：
/// 1. 注入 `defineTool` 全局函数与 `ctx.tools.register` 桥（替代
///    `@deepseek-ai/dsh-tools` 依赖，插件源码中的 import 语句会被剥离）；
/// 2. 执行插件源码并调用 `apply(ctx)`，收集注册的工具；
/// 3. 工具调用通过 Promise 包装 + 任务队列轮询，兼容同步与异步 execute。
///
/// 安全边界与 JsSandboxService 一致：无网络、无文件系统、无 Dart 桥接
/// （插件拿不到宿主能力），256KB JS 栈上限 + Dart 看门狗超时强杀。
class DshRuntime {
  DshRuntime._();
  static final DshRuntime instance = DshRuntime._();

  static const String _consoleChannel = 'MotaDshConsole';
  static const int _stackSize = 256 * 1024;

  /// 发现插件注册的工具清单（install / enable 时调用）
  Future<List<DshToolDef>> discoverTools(
    String pluginSource, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final result = await _run(_DshTask(
      pluginSource: pluginSource,
      mode: _DshMode.discover,
      timeout: timeout,
    ));
    if (!result.ok) {
      throw DshPluginException(result.error ?? '插件加载失败');
    }
    final decoded = jsonDecode(result.value ?? '[]');
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((m) => DshToolDef.fromJson(m.cast<String, dynamic>()))
        .where((t) => t.name.isNotEmpty)
        .toList();
  }

  /// 调用插件工具
  Future<DshToolResult> callTool({
    required String pluginSource,
    required String toolName,
    required Map<String, dynamic> arguments,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    return _run(_DshTask(
      pluginSource: pluginSource,
      mode: _DshMode.call,
      toolName: toolName,
      argsJson: jsonEncode(arguments),
      timeout: timeout,
    ));
  }

  Future<DshToolResult> _run(_DshTask task) async {
    final completer = Completer<DshToolResult>();
    final port = ReceivePort();
    Isolate? isolate;
    Timer? watchdog;

    void finish(DshToolResult result) {
      if (completer.isCompleted) return;
      watchdog?.cancel();
      completer.complete(result);
      port.close();
    }

    port.listen((message) {
      if (message is Map) {
        finish(DshToolResult(
          ok: message['ok'] == true,
          value: message['value']?.toString(),
          error: message['error']?.toString(),
          output: message['output']?.toString() ?? '',
        ));
      } else {
        finish(const DshToolResult(ok: false, error: '沙箱返回了无法识别的结果'));
      }
    });

    try {
      isolate = await Isolate.spawn(_isolateEntry, _DshEnvelope(task, port.sendPort));
    } catch (e) {
      finish(DshToolResult(ok: false, error: '插件沙箱启动失败: $e'));
      return completer.future;
    }

    watchdog = Timer(task.timeout, () {
      isolate?.kill(priority: Isolate.immediate);
      finish(const DshToolResult(
        ok: false,
        timedOut: true,
        error: '插件执行超时，已被强制终止',
      ));
    });

    return completer.future;
  }

  // ---------- isolate 内部 ----------

  static void _isolateEntry(_DshEnvelope envelope) async {
    final task = envelope.task;
    final logs = <String>[];
    try {
      final runtime = QuickJsRuntime2(stackSize: _stackSize);
      runtime.onMessage(_consoleChannel, (dynamic args) {
        final list = args is List ? args : <dynamic>[args];
        final parts = list.map((e) => e?.toString() ?? '').toList();
        if (parts.isNotEmpty) parts.removeAt(0);
        logs.add(parts.join(' '));
      });

      // 1. 预注入：defineTool + ctx 桥
      runtime.evaluate(_prelude);

      // 2. 插件源码 ESM → 普通脚本（剥离 import / export）
      runtime.evaluate(transformSource(task.pluginSource), sourceUrl: 'dsh-plugin.js');

      // 3. 调用 apply(ctx)
      final applyResult = runtime.evaluate('typeof apply === "function" ? (apply(ctx), "applied") : "no-apply"');
      if (applyResult.isError) {
        _reply(envelope, DshToolResult(
          ok: false,
          error: '插件 apply() 执行失败：${applyResult.stringResult}',
          output: logs.join('\n'),
        ));
        return;
      }
      if (applyResult.stringResult == 'no-apply') {
        _reply(envelope, DshToolResult(
          ok: false,
          error: '插件入口未导出 apply(ctx) 函数（不符合 DSH 插件契约）',
          output: logs.join('\n'),
        ));
        return;
      }

      if (task.mode == _DshMode.discover) {
        final defs = runtime.evaluate(
          'JSON.stringify(__mota_tools.map(function(t){return {name:String(t.name),description:String(t.description==null?"":t.description),parameters:(t.parameters==null?{}:t.parameters)}}))',
        );
        if (defs.isError) {
          _reply(envelope, DshToolResult(
            ok: false,
            error: '读取工具清单失败：${defs.stringResult}',
            output: logs.join('\n'),
          ));
          return;
        }
        _reply(envelope, DshToolResult(
          ok: true,
          value: defs.stringResult,
          output: logs.join('\n'),
        ));
        return;
      }

      // 4. 工具调用（Promise 包装，兼容同步 / 异步 execute）
      runtime.evaluate('''
        var __mota_state = {done:false, ok:true, value:null, error:null};
        var __mota_target = __mota_tools.find(function(t){return t.name === ${jsonEncode(task.toolName)};});
        if (!__mota_target) {
          __mota_state.done = true; __mota_state.ok = false;
          __mota_state.error = '工具未注册：${task.toolName}';
        } else {
          Promise.resolve().then(function(){
            return __mota_target.execute(JSON.parse(${jsonEncode(task.argsJson)}));
          }).then(function(r){
            __mota_state.done = true; __mota_state.value = (r === undefined ? null : r);
          }, function(e){
            __mota_state.done = true; __mota_state.ok = false;
            __mota_state.error = String(e && e.message ? e.message : e);
          });
        }
      ''');

      // 轮询任务队列直到 Promise 完成
      final deadline = DateTime.now().add(task.timeout);
      while (true) {
        runtime.executePendingJob();
        final state = runtime.evaluate('JSON.stringify(__mota_state)');
        if (state.isError) {
          _reply(envelope, DshToolResult(
            ok: false,
            error: '读取工具执行状态失败：${state.stringResult}',
            output: logs.join('\n'),
          ));
          return;
        }
        final decoded = jsonDecode(state.stringResult);
        if (decoded is Map && decoded['done'] == true) {
          final ok = decoded['ok'] == true;
          if (!ok) {
            _reply(envelope, DshToolResult(
              ok: false,
              error: '工具执行异常：${decoded['error']}',
              output: logs.join('\n'),
            ));
            return;
          }
          final valueEval = runtime.evaluate('JSON.stringify(__mota_state.value)');
          _reply(envelope, DshToolResult(
            ok: true,
            value: valueEval.isError ? null : valueEval.stringResult,
            output: logs.join('\n'),
          ));
          return;
        }
        if (DateTime.now().isAfter(deadline)) {
          _reply(envelope, DshToolResult(
            ok: false,
            timedOut: true,
            error: '工具执行超时',
            output: logs.join('\n'),
          ));
          return;
        }
        // 让出事件循环：给 QuickJS 的 dispatch / microtask 处理机会
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    } catch (e) {
      _reply(envelope, DshToolResult(
        ok: false,
        error: '插件沙箱内部错误: $e',
        output: logs.join('\n'),
      ));
    }
  }

  static void _reply(_DshEnvelope envelope, DshToolResult result) {
    envelope.replyTo.send({
      'ok': result.ok,
      'value': result.value,
      'error': result.error,
      'output': result.output,
    });
  }

  /// 预注入脚本：defineTool 全局 + ctx 桥
  static const String _prelude = '''
var __mota_tools = [];
function defineTool(def) { if (def && def.name) { __mota_tools.push(def); } return def; }
var ctx = {
  tools: {
    register: function(t) {
      if (Array.isArray(t)) { for (var i = 0; i < t.length; i++) defineTool(t[i]); }
      else { defineTool(t); }
    }
  }
};
''';

  /// ESM → 普通脚本转换（括号深度跟踪，容忍无分号风格）：
  /// - 剥离 import 语句（`@deepseek-ai/dsh-tools` 等由预注入的 defineTool 替代）
  /// - 剥离 export 前缀（`export function apply(ctx)` → `function apply(ctx)`）
  static String transformSource(String source) {
    final out = <String>[];
    var skippingImport = false;
    var depth = 0;
    for (final line in source.split('\n')) {
      if (skippingImport) {
        depth += _depthDelta(line);
        out.add('');
        if (depth <= 0) {
          depth = 0;
          skippingImport = false;
        }
        continue;
      }
      final trimmed = line.trimLeft();
      if (RegExp(r'^import\b').hasMatch(trimmed)) {
        out.add('');
        final delta = _depthDelta(line);
        if (delta > 0) {
          // 多行 import：跳到括号闭合
          depth = delta;
          skippingImport = true;
        }
        // 单行 import（有无分号均视为完整语句）
        continue;
      }
      out.add(line.replaceFirstMapped(
        RegExp(r'^(\s*)export\s+(default\s+)?'),
        (m) => m.group(1) ?? '',
      ));
    }
    return out.join('\n');
  }

  /// 计算一行代码的括号深度变化（忽略字符串字面量内的括号）
  static int _depthDelta(String line) {
    var depth = 0;
    var inString = false;
    String? quote;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (inString) {
        if (c == quote && (i == 0 || line[i - 1] != r'\')) {
          inString = false;
        }
        continue;
      }
      if (c == '"' || c == "'" || c == '`') {
        inString = true;
        quote = c;
        continue;
      }
      if (c == '(' || c == '[' || c == '{') {
        depth++;
      } else if (c == ')' || c == ']' || c == '}') {
        depth--;
      }
    }
    return depth;
  }
}

/// isolate 任务描述
class _DshTask {
  _DshTask({
    required this.pluginSource,
    required this.mode,
    this.toolName,
    this.argsJson,
    required this.timeout,
  });

  final String pluginSource;
  final _DshMode mode;
  final String? toolName;
  final String? argsJson;
  final Duration timeout;
}

enum _DshMode { discover, call }

class _DshEnvelope {
  _DshEnvelope(this.task, this.replyTo);
  final _DshTask task;
  final SendPort replyTo;
}
