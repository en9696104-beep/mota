/// Work 工作台原生能力桥（Dart 侧）
///
/// 对应 Kotlin `WorkNative`（MethodChannel: com.mota.app/work_native）：
/// - 无障碍：tap / swipe / inputText / readScreen
/// - Shizuku：状态探测 / 授权请求 / shell 执行
/// - Root：su 状态探测 / shell 执行
///
/// 所有调用对「非 Android 平台 / 通道未实现」安全降级（返回 false/null/错误串），
/// 由上层执行器转为可读的失败原因，绝不静默成功。
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

class WorkNativeChannel {
  WorkNativeChannel._();

  static const MethodChannel _channel =
      MethodChannel('com.mota.app/work_native');

  /// 仅 Android 真机有效（其他平台/测试环境一律降级为「不可用」）
  static bool get supported {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  static Future<T?> _invoke<T>(String method,
      [Map<String, Object?>? args]) async {
    if (!supported) return null;
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      throw WorkNativeException(e.code, e.message ?? '原生调用失败');
    }
  }

  // ---------------------------------------------------------------- 无障碍

  static Future<bool> accessibilityEnabled() async =>
      (await _invoke<bool>('accessibilityStatus')) ?? false;

  static Future<void> openAccessibilitySettings() =>
      _invoke<void>('openAccessibilitySettings');

  static Future<bool> tap(double x, double y) async =>
      (await _invoke<bool>('tap', <String, Object?>{'x': x, 'y': y})) ?? false;

  static Future<bool> swipe(
    double x1,
    double y1,
    double x2,
    double y2, {
    int durationMs = 300,
  }) async =>
      (await _invoke<bool>('swipe', <String, Object?>{
        'x1': x1,
        'y1': y1,
        'x2': x2,
        'y2': y2,
        'duration': durationMs,
      })) ??
      false;

  static Future<bool> inputText(String text) async =>
      (await _invoke<bool>('inputText', <String, Object?>{'text': text})) ??
      false;

  static Future<String?> readScreen() => _invoke<String>('readScreen');

  // ---------------------------------------------------------------- 设备信息

  static Future<Map<String, dynamic>?> deviceInfo() async {
    final map = await _invoke<Map<Object?, Object?>>('deviceInfo');
    return map?.cast<String, dynamic>();
  }

  // ---------------------------------------------------------------- Shizuku

  static Future<Map<String, dynamic>?> shizukuStatus() async {
    final map = await _invoke<Map<Object?, Object?>>('shizukuStatus');
    return map?.cast<String, dynamic>();
  }

  static Future<void> requestShizukuPermission() =>
      _invoke<void>('requestShizukuPermission');

  /// 经 Shizuku 执行 shell；未就绪时抛 [WorkNativeException]
  static Future<String> shizukuExec(String cmd) async {
    final out = await _invoke<String>('shizukuExec', <String, Object?>{'cmd': cmd});
    if (out == null) {
      throw const WorkNativeException('UNSUPPORTED', '当前平台不支持 Shizuku');
    }
    return out;
  }

  // ---------------------------------------------------------------- Root

  static Future<Map<String, dynamic>?> rootStatus() async {
    final map = await _invoke<Map<Object?, Object?>>('rootStatus');
    return map?.cast<String, dynamic>();
  }

  /// 经 su 执行 shell；未 Root 时抛 [WorkNativeException]
  static Future<String> rootExec(String cmd) async {
    final out = await _invoke<String>('rootExec', <String, Object?>{'cmd': cmd});
    if (out == null) {
      throw const WorkNativeException('UNSUPPORTED', '当前平台不支持 Root');
    }
    return out;
  }
}

/// 原生调用失败（携带可读原因）
class WorkNativeException implements Exception {
  const WorkNativeException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}
