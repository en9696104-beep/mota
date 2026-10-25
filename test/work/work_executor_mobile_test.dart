import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mota/work/models/work_permission.dart';
import 'package:mota/work/services/work_executor_desktop.dart';
import 'package:mota/work/services/work_executor_mobile.dart';

/// 移动执行器测试（VM 环境无原生通道，覆盖降级路径与委托路径；
/// 真机上的无障碍/Shizuku/Root  happy path 需设备验证，见交付报告）
void main() {
  late Directory tmpDir;
  const executor = MobileWorkExecutor();

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('work_mobile_');
  });

  tearDown(() async {
    await tmpDir.delete(recursive: true);
  });

  test('能力位不足先于原生调用被拒', () async {
    final viewOnly = WorkPermissions.tierById('view_only')!;
    final res = await executor.execute(
      'tap',
      viewOnly,
      args: const <String, dynamic>{'x': 100, 'y': 200},
    );
    expect(res.ok, isFalse);
    expect(res.output, contains('不包含该操作'));
  });

  test('tap 缺坐标返回可读错误', () async {
    final accessibility = WorkPermissions.tierById('accessibility')!;
    final res = await executor.execute('tap', accessibility);
    expect(res.ok, isFalse);
    expect(res.output, contains('tap 需要坐标'));
  });

  test('swipe 缺坐标返回可读错误', () async {
    final accessibility = WorkPermissions.tierById('accessibility')!;
    final res = await executor.execute(
      'swipe',
      accessibility,
      target: '100,200',
    );
    expect(res.ok, isFalse);
    expect(res.output, contains('swipe 需要坐标'));
  });

  test('VM 环境无原生通道：UI 动作安全降级为失败（不静默成功）', () async {
    final accessibility = WorkPermissions.tierById('accessibility')!;
    for (final (action, args, target) in <(String, Map<String, dynamic>, String?)>[
      ('tap', const <String, dynamic>{'x': 1, 'y': 2}, null),
      ('input_text', const <String, dynamic>{'text': 'hi'}, null),
      ('read_screen', const <String, dynamic>{}, null),
      ('device_info', const <String, dynamic>{}, null),
    ]) {
      final res = await executor.execute(action, accessibility,
          args: args, target: target);
      expect(res.ok, isFalse, reason: '$action 在无原生通道环境不应成功');
      expect(res.output, isNotEmpty, reason: '$action 失败必须有可读原因');
    }
  });

  test('文件类动作委托桌面实现（读写正常）', () async {
    final file = File('${tmpDir.path}/m.txt');
    final full = WorkPermissions.tierById('full_access')!;
    final write = await executor.execute(
      'write_file',
      full,
      target: file.path,
      args: const <String, dynamic>{'content': 'mobile-bridge'},
    );
    expect(write.ok, isTrue);
    final read = await executor.execute('read_file', full, target: file.path);
    expect(read.ok, isTrue);
    expect(read.output, 'mobile-bridge');
  });

  test('restricted 档白名单外删除被拒（委托路径同样收敛）', () async {
    DesktopWorkExecutor.restrictedRoots = <String>[tmpDir.path];
    final restricted = WorkPermissions.tierById('restricted_files')!;
    final res = await executor.execute(
      'delete_file',
      restricted,
      target: '/etc/hosts',
    );
    expect(res.ok, isFalse);
    expect(res.output, contains('系统路径禁止删除'));
    DesktopWorkExecutor.restrictedRoots = <String>[];
  });

  test('root 档 run_shell 在 VM 降级为可读失败', () async {
    final root = WorkPermissions.tierById('root')!;
    final res = await executor.execute('run_shell', root, target: 'id');
    expect(res.ok, isFalse);
    expect(res.output, isNotEmpty);
  });

  test('shizuku 档 run_shell 在 VM 降级为可读失败', () async {
    final shizuku = WorkPermissions.tierById('shizuku')!;
    final res = await executor.execute('run_shell', shizuku, target: 'id');
    expect(res.ok, isFalse);
    expect(res.output, isNotEmpty);
  });

  test('target 形式坐标被正确解析（"x,y"）', () async {
    final accessibility = WorkPermissions.tierById('accessibility')!;
    // VM 无通道会失败，但错误原因应是「手势分发失败」而非「需要坐标」，
    // 证明坐标解析走通
    final res = await executor.execute(
      'tap',
      accessibility,
      target: '120.5, 240.5',
    );
    expect(res.output, contains('手势分发失败'));
  });
}
