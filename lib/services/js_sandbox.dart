import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_js/flutter_js.dart';

/// JS 沙箱单次执行的结构化结果。
class JsExecResult {
  /// 是否正常执行完毕（无 JS 异常、未超时、未被预检拒绝）。
  final bool ok;

  /// console.log/info/warn/error 捕获到的输出（按行拼接）。
  final String output;

  /// 最后一条表达式语句的返回值（字符串化）。
  final String? returnValue;

  /// 失败原因：JS 异常信息 / 超时提示 / 预检拒绝原因。
  final String? error;

  /// 是否因超过执行时限被看门狗强制终止。
  final bool timedOut;

  /// 实际执行耗时（毫秒）。
  final int durationMs;

  const JsExecResult({
    required this.ok,
    this.output = '',
    this.returnValue,
    this.error,
    this.timedOut = false,
    this.durationMs = 0,
  });

  bool get hasOutput => output.trim().isNotEmpty;

  /// 供 UI 展示的一行摘要。
  String get summary {
    if (!ok) return error ?? '执行失败';
    final parts = <String>[];
    if (hasOutput) parts.add(output);
    final ret = returnValue;
    if (ret != null && ret.isNotEmpty && ret != 'undefined') {
      parts.add('返回值: $ret');
    }
    return parts.isEmpty ? '执行完成（无输出）' : parts.join('\n');
  }

  @override
  String toString() =>
      'JsExecResult(ok: $ok, timedOut: $timedOut, durationMs: $durationMs)';
}

/// 沙箱内部任务消息（跨 isolate 传递）。
class _JsTask {
  final String code;
  final int stackSize;
  final SendPort replyTo;
  const _JsTask(this.code, this.stackSize, this.replyTo);
}

/// QuickJS 沙箱服务。
///
/// 防护策略（多层）：
/// 1. **静态预检**：执行前拦截 while(true) / for(;;) 等明显死循环写法；
/// 2. **isolate 隔离**：JS 运行在独立 isolate，即使死循环卡死原生 FFI 调用，
///    也只阻塞后台线程，UI 线程保持响应；
/// 3. **看门狗**：Dart 侧超时后强制终止 isolate 并立即返回超时结果；
/// 4. **引擎硬限制**：QuickJS 层设置栈上限（默认 256KB），深递归抛 JS 异常；
///    上限经过实测校准——过大的 JS 栈上限会让原生栈先于 JS 栈检查耗尽，
///    导致整个进程段错误（详见 defaultStackSize 注释）。
///
/// 已知限制（均已实测验证）：
/// - 当前 QuickJS 原生构建（Android libfastdev_quickjs_runtime.so 与
///   flutter_js 自带 Linux 库）均未导出 jsSetMemoryLimit，内存上限暂不生效，
///   execute() 的 memoryLimit 参数为预留项；
/// - QuickJsRuntime2 的 timeout 参数依赖原生中断处理器，fastdev 版虽注册了
///   中断回调但计时种子无人写入（反汇编验证），同样不生效，
///   超时防护完全由 Dart 侧看门狗承担。
class JsSandboxService {
  JsSandboxService._();
  static final JsSandboxService instance = JsSandboxService._();

  /// 默认执行时限：5 秒。
  static const int defaultTimeoutMs = 5000;

  /// 默认内存上限：64MB。
  static const int defaultMemoryLimit = 64 * 1024 * 1024;

  /// 默认栈上限：256KB（深递归会触发 QuickJS 的 stack overflow 异常）。
  /// 实测依据（flutter_js 自带 Linux 原生库、spawned isolate）：
  /// isolate 线程原生栈约 4MB；JS 栈上限 512KB 时 277 层递归正常抛错，
  /// 1MB 时直接段错误（原生栈先于 JS 栈检查耗尽）。取 2 倍安全余量定 256KB，
  /// 约支持 140 层合法递归，足够覆盖常规数据处理脚本。
  static const int defaultStackSize = 256 * 1024;

  /// console 输出通道名（默认的 ConsoleLog 通道已被库内部占用且不可重复注册）。
  static const String _consoleChannel = 'MotaConsole';

  /// 明显死循环特征：while(true) / while(1) / for(;;) / for( ; ; )。
  static final RegExp _infiniteLoopPattern = RegExp(
    r'while\s*\(\s*(true|1)\s*\)|for\s*\(\s*;\s*;?\s*\)',
    caseSensitive: false,
  );

  /// 执行一段 JS 代码，返回结构化结果。保证不向调用方抛出异常。
  ///
  /// [timeout] 执行时限（默认 5 秒），超时由看门狗强制终止并返回 timedOut 结果；
  /// [memoryLimit] 内存上限（默认 64MB），当前 QuickJS 原生构建未导出
  /// jsSetMemoryLimit 符号，该参数暂不生效，为预留项。
  Future<JsExecResult> execute(
    String code, {
    Duration? timeout,
    int? memoryLimit,
  }) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      return const JsExecResult(ok: false, error: '脚本内容为空');
    }
    if (_infiniteLoopPattern.hasMatch(trimmed)) {
      return const JsExecResult(
        ok: false,
        error: '检测到疑似无限循环（while(true) / for(;;)），'
            '沙箱已拒绝执行。请添加退出条件或改用有界循环。',
      );
    }

    final effectiveTimeout =
        timeout ?? const Duration(milliseconds: defaultTimeoutMs);
    final completer = Completer<JsExecResult>();
    final port = ReceivePort();
    Isolate? isolate;
    Timer? watchdog;

    void finish(JsExecResult result) {
      if (completer.isCompleted) return;
      watchdog?.cancel();
      completer.complete(result);
      port.close();
    }

    port.listen((message) {
      if (message is Map) {
        finish(JsExecResult(
          ok: message['ok'] == true,
          output: message['output']?.toString() ?? '',
          returnValue: message['returnValue']?.toString(),
          error: message['error']?.toString(),
          durationMs: message['durationMs'] is int
              ? message['durationMs'] as int
              : 0,
        ));
      } else {
        finish(const JsExecResult(ok: false, error: '沙箱返回了无法识别的结果'));
      }
    });

    try {
      isolate = await Isolate.spawn(
        _isolateEntry,
        _JsTask(trimmed, defaultStackSize, port.sendPort),
      );
    } catch (e) {
      finish(JsExecResult(ok: false, error: '沙箱启动失败: $e'));
      return completer.future;
    }

    watchdog = Timer(effectiveTimeout, () {
      // 卡死在原生 FFI 循环里的 isolate 无法立即响应 kill，
      // 因此不等待 kill 完成，直接向调用方返回超时结果。
      isolate?.kill(priority: Isolate.immediate);
      finish(JsExecResult(
        ok: false,
        timedOut: true,
        error: '执行超时（超过 ${effectiveTimeout.inMilliseconds ~/ 1000} 秒），'
            '已被强制终止。请检查是否存在死循环或耗时操作。',
        durationMs: effectiveTimeout.inMilliseconds,
      ));
    });

    return completer.future;
  }

  /// 在独立 isolate 中创建 JS 运行时。
  static JavascriptRuntime _createRuntime(_JsTask task) {
    // 注意：不传 memoryLimit —— 当前 QuickJS 原生构建未导出
    // jsSetMemoryLimit 符号，传入会导致 FFI 符号查找失败。
    if (Platform.isAndroid || Platform.isWindows || Platform.isLinux) {
      return QuickJsRuntime2(stackSize: task.stackSize);
    }
    // iOS 等平台走 JavaScriptCore。
    return getJavascriptRuntime(
      forceJavascriptCoreOnAndroid: false,
      xhr: false,
      extraArgs: {'stackSize': task.stackSize},
    );
  }

  /// isolate 入口：注入 console 捕获、执行用户代码、回传结构化结果。
  static void _isolateEntry(_JsTask task) {
    final logs = <String>[];
    final sw = Stopwatch()..start();
    JsExecResult result;
    try {
      final runtime = _createRuntime(task);
      // 默认 console 通道已被库占用且只 print，这里覆盖为可捕获实现。
      runtime.onMessage(_consoleChannel, (dynamic args) {
        final list = args is List ? args : <dynamic>[args];
        final parts = list.map((e) => e?.toString() ?? '').toList();
        if (parts.isNotEmpty) parts.removeAt(0); // 去掉 'log'/'warn' 标签
        logs.add(parts.join(' '));
      });
      runtime.evaluate('''
        var console = {
          log:   function() { sendMessage('$_consoleChannel', JSON.stringify(['log', ...arguments])); },
          info:  function() { sendMessage('$_consoleChannel', JSON.stringify(['info', ...arguments])); },
          warn:  function() { sendMessage('$_consoleChannel', JSON.stringify(['warn', ...arguments])); },
          error: function() { sendMessage('$_consoleChannel', JSON.stringify(['error', ...arguments])); }
        };
      ''');
      final eval = runtime.evaluate(task.code, sourceUrl: 'mota-sandbox.js');
      if (eval.isError) {
        result = JsExecResult(
          ok: false,
          output: logs.join('\n'),
          error: eval.stringResult,
          durationMs: sw.elapsedMilliseconds,
        );
      } else {
        result = JsExecResult(
          ok: true,
          output: logs.join('\n'),
          returnValue: eval.stringResult,
          durationMs: sw.elapsedMilliseconds,
        );
      }
      runtime.dispose();
    } catch (e) {
      result = JsExecResult(
        ok: false,
        output: logs.join('\n'),
        error: '沙箱内部错误: $e',
        durationMs: sw.elapsedMilliseconds,
      );
    }
    task.replyTo.send({
      'ok': result.ok,
      'output': result.output,
      'returnValue': result.returnValue,
      'error': result.error,
      'durationMs': result.durationMs,
    });
  }
}
