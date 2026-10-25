/// 移动端任务执行器 —— UI 自动化与特权 shell（对应 Android 三档系统权限）
///
/// 动作路由：
/// - tap / swipe / input_text / read_screen → 无障碍服务（原生通道）
/// - run_shell → shizuku 档走 Shizuku UserService；root 档走 su
/// - device_info → 原生 Build 信息
/// - 文件类动作 → 委托 [DesktopWorkExecutor]（dart:io 在 Android 同样可用，
///   受 restricted 白名单收敛；真实产品可换 scoped-storage 适配，见交付报告）
///
/// 与桌面执行器同一套双重防线：执行前再校验能力位，失败一律回传可读原因。
library;

import '../models/work_permission.dart';
import 'work_executor_desktop.dart';
import 'work_native_channel.dart';

class MobileWorkExecutor {
  const MobileWorkExecutor();

  static const DesktopWorkExecutor _base = DesktopWorkExecutor();

  Future<ExecResult> execute(
    String action,
    WorkPermissionTier tier, {
    String? target,
    Map<String, dynamic> args = const <String, dynamic>{},
  }) async {
    // 双重防线：执行器侧再校验能力位
    if (!WorkCapabilities.allows(tier, action)) {
      return ExecResult(false, '权限档位「${tier.label}」不包含该操作');
    }
    try {
      switch (action) {
        case 'device_info':
          return await _deviceInfo();
        case 'tap':
          final x = _numArg(args, 'x') ?? _parsePair(target)?.$1;
          final y = _numArg(args, 'y') ?? _parsePair(target)?.$2;
          if (x == null || y == null) {
            return const ExecResult(false, 'tap 需要坐标：args.x/args.y 或 target "x,y"');
          }
          final ok = await WorkNativeChannel.tap(x, y);
          return ExecResult(ok, ok ? '已点击 ($x, $y)' : '手势分发失败：无障碍服务未开启或系统拒绝');
        case 'swipe':
          final p = _parseQuad(args, target);
          if (p == null) {
            return const ExecResult(false, 'swipe 需要坐标：args.x1/y1/x2/y2 或 target "x1,y1,x2,y2"');
          }
          final ok = await WorkNativeChannel.swipe(
            p.$1, p.$2, p.$3, p.$4,
            durationMs: (args['duration'] as num?)?.toInt() ?? 300,
          );
          return ExecResult(ok, ok ? '已滑动 (${p.$1},${p.$2})→(${p.$3},${p.$4})' : '手势分发失败：无障碍服务未开启或系统拒绝');
        case 'input_text':
          final text = (args['text'] as String?) ?? target ?? '';
          if (text.isEmpty) return const ExecResult(false, 'input_text 需要 args.text');
          final ok = await WorkNativeChannel.inputText(text);
          return ExecResult(ok, ok ? '已输入 ${text.length} 字符' : '输入失败：未找到焦点输入框或无障碍服务未开启');
        case 'read_screen':
          final text = await WorkNativeChannel.readScreen();
          if (text == null) {
            return const ExecResult(false, '读屏失败：无障碍服务未开启');
          }
          return ExecResult(true, text);
        case 'run_shell':
          if (target == null || target.isEmpty) {
            return const ExecResult(false, 'run_shell 需要命令字符串');
          }
          // root 档走 su；shizuku 档走 Shizuku UserService
          if (tier.id == 'root') {
            final out = await WorkNativeChannel.rootExec(target);
            return ExecResult(true, out);
          }
          final out = await WorkNativeChannel.shizukuExec(target);
          return ExecResult(true, out);
        default:
          // 文件类（list/read/write/delete）委托桌面实现
          return await _base.execute(action, tier, target: target, args: args);
      }
    } on WorkNativeException catch (e) {
      return ExecResult(false, e.message);
    } catch (e) {
      return ExecResult(false, '执行异常: $e');
    }
  }

  Future<ExecResult> _deviceInfo() async {
    final info = await WorkNativeChannel.deviceInfo();
    if (info == null) {
      return const ExecResult(false, '设备信息获取失败：原生通道不可用');
    }
    final text = info.entries.map((e) => '${e.key}=${e.value}').join(' ');
    return ExecResult(true, text);
  }

  static double? _numArg(Map<String, dynamic> args, String key) {
    final v = args[key];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  /// 解析 "x,y" 形式的 target
  static (double, double)? _parsePair(String? target) {
    if (target == null) return null;
    final parts = target.split(',');
    if (parts.length != 2) return null;
    final x = double.tryParse(parts[0].trim());
    final y = double.tryParse(parts[1].trim());
    if (x == null || y == null) return null;
    return (x, y);
  }

  /// 解析四元坐标（args 优先，target "x1,y1,x2,y2" 兜底）
  static (double, double, double, double)? _parseQuad(
    Map<String, dynamic> args,
    String? target,
  ) {
    final x1 = _numArg(args, 'x1');
    final y1 = _numArg(args, 'y1');
    final x2 = _numArg(args, 'x2');
    final y2 = _numArg(args, 'y2');
    if (x1 != null && y1 != null && x2 != null && y2 != null) {
      return (x1, y1, x2, y2);
    }
    if (target == null) return null;
    final parts = target.split(',');
    if (parts.length != 4) return null;
    final nums = parts.map((p) => double.tryParse(p.trim())).toList();
    if (nums.any((n) => n == null)) return null;
    return (nums[0]!, nums[1]!, nums[2]!, nums[3]!);
  }
}
