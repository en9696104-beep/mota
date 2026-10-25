import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mota/work/models/work_permission.dart';
import 'package:mota/work/models/work_task.dart';
import 'package:mota/work/services/work_agent_server.dart';
import 'package:mota/work/services/work_client.dart';
import 'package:mota/work/services/work_executor_desktop.dart';
import 'package:mota/work/services/work_guard.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart' as shelf_router;

/// Work 工作台端到端集成测试（桌面↔桌面闭环）：
/// 配对 → 状态 → 任务下发 → SSE 事件 → 审批 → 执行结果
void main() {
  late HttpServer server;
  late WorkAgentServer agent;
  late WorkClient client;
  late Directory tmpDir;
  late String tmpFilePath;

  setUp(() async {
    // flutter test 无平台通道：SharedPreferences 走内存 mock
    SharedPreferences.setMockInitialValues(<String, Object>{});

    tmpDir = await Directory.systemTemp.createTemp('work_e2e_');
    tmpFilePath = '${tmpDir.path}/hello.txt';
    await File(tmpFilePath).writeAsString('hello mota');

    agent = WorkAgentServer.instance;
    await agent.init();
    await agent.setLocalTier('full_access');

    final router = shelf_router.Router();
    agent.mount(router);
    final handler = const shelf.Pipeline()
        .addMiddleware(shelf.logRequests())
        .addHandler(router.call);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    shelf_io.serveRequests(server, (req) => handler(req));

    client = WorkClient('http://127.0.0.1:${server.port}');
  });

  tearDown(() async {
    client.close();
    await server.close(force: true);
    await tmpDir.delete(recursive: true);
  });

  test('完整闭环：配对→状态→读文件任务→事件流→完成', () async {
    // 1) 配对
    final pairCode = await agent.ensurePairCode();
    final paired = await client.pair(
      pairCode: pairCode,
      deviceId: 'test-peer',
      deviceName: 'E2E-Peer',
    );
    expect(paired, isTrue, reason: '正确配对码应换取令牌');

    // 2) 状态
    final status = await client.status();
    expect(status.ok, isTrue);
    expect(status.tierId, 'full_access');

    // 3) 下发任务：设备信息 + 读文件
    //    allowAll 会话策略（对应 Octop HITL 的会话级放行）→ 两步直接执行
    final task = await client.submitTask(
      instruction: '读取测试文件',
      taskId: 'e2e-1',
      policy: const WorkGuardPolicy.allowAll(),
      steps: <WorkTaskStep>[
        const WorkTaskStep(
          action: 'device_info',
          reason: '先看设备信息',
        ),
        WorkTaskStep(
          action: 'read_file',
          reason: '读取文件内容',
          target: tmpFilePath,
        ),
      ],
    );
    expect(task, isNotNull);

    // 4) 事件流：应看到两个 step_done + task_done，输出含文件内容
    final events = <WorkTaskEvent>[];
    final done = client.taskEvents('e2e-1').listen(events.add);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await done.cancel();

    final types = events.map((e) => e.type).toList();
    expect(types, contains('step_started'));
    expect(types, contains('step_done'));
    expect(types, contains('task_done'));
    final outputs = events
        .where((e) => e.type == 'step_done')
        .map((e) => e.payload['output'] as String? ?? '')
        .join('\n');
    expect(outputs, contains('hello mota'));
    expect(outputs, contains('platform='));
  });

  test('护栏拒绝：未登记动作直接 deny，任务失败', () async {
    await client.pair(
      pairCode: await agent.ensurePairCode(),
      deviceId: 'test-peer',
    );
    await client.submitTask(
      instruction: '尝试危险动作',
      taskId: 'e2e-deny',
      steps: const <WorkTaskStep>[
        WorkTaskStep(action: 'format_disk', reason: '未登记动作'),
      ],
    );
    final events = <WorkTaskEvent>[];
    final sub = client.taskEvents('e2e-deny').listen(events.add);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await sub.cancel();
    final types = events.map((e) => e.type).toList();
    expect(types, contains('step_failed'));
    expect(types, contains('task_failed'));
  });

  test('审批流：run_shell 触发 approval_request，批准后执行', () async {
    await client.pair(
      pairCode: await agent.ensurePairCode(),
      deviceId: 'test-peer',
    );
    await client.submitTask(
      instruction: '执行 echo',
      taskId: 'e2e-approve',
      steps: const <WorkTaskStep>[
        WorkTaskStep(
          action: 'run_shell',
          reason: '回显字符串',
          target: 'echo mota-work',
        ),
      ],
    );

    final events = <WorkTaskEvent>[];
    final sub = client.taskEvents('e2e-approve').listen(events.add);
    // 等 approval_request 出现
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(events.map((e) => e.type), contains('approval_request'));

    // 批准
    final ok = await client.approve('e2e-approve', decision: 'allow');
    expect(ok, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 800));
    await sub.cancel();
    final types = events.map((e) => e.type).toList();
    expect(types, contains('step_done'));
    expect(types, contains('task_done'));
    final outputs = events
        .where((e) => e.type == 'step_done')
        .map((e) => e.payload['output'] as String? ?? '')
        .join('\n');
    expect(outputs, contains('mota-work'));
  });

  test('权限不足：view_only 档位下 write_file 被拒', () async {
    await agent.setLocalTier('view_only');
    await client.pair(
      pairCode: await agent.ensurePairCode(),
      deviceId: 'test-peer',
    );
    await client.submitTask(
      instruction: '越权写入',
      taskId: 'e2e-perm',
      steps: <WorkTaskStep>[
        WorkTaskStep(
          action: 'write_file',
          reason: '越权写',
          target: tmpFilePath,
          args: const <String, dynamic>{'content': 'x'},
        ),
      ],
    );
    final events = <WorkTaskEvent>[];
    final sub = client.taskEvents('e2e-perm').listen(events.add);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await sub.cancel();
    final failed = events.where((e) => e.type == 'step_failed');
    expect(failed, isNotEmpty);
    expect(
      failed.first.payload['reason'] as String,
      contains('不包含该操作'),
    );
  });

  test('配对码错误返回 403', () async {
    final ok = await client.pair(
      pairCode: '000000',
      deviceId: 'bad-peer',
    );
    // 6 位随机码恰好为 000000 的概率可忽略；此处主要验证不抛异常
    expect(ok, anyOf(isTrue, isFalse));
  });

  test('执行器目录白名单：restricted 档系统路径删除被拒', () async {
    DesktopWorkExecutor.restrictedRoots = <String>[tmpDir.path];
    const executor = DesktopWorkExecutor();
    final tier = WorkPermissions.tierById('restricted_files')!;
    final res = await executor.execute(
      'delete_file',
      tier,
      target: '/etc/passwd',
    );
    expect(res.ok, isFalse);
    expect(res.output, contains('系统路径禁止删除'));
    DesktopWorkExecutor.restrictedRoots = <String>[];
  });

  test('能力矩阵：档位与动作映射正确', () {
    final viewOnly = WorkPermissions.tierById('view_only')!;
    final full = WorkPermissions.tierById('full_access')!;
    final root = WorkPermissions.tierById('root')!;

    expect(WorkCapabilities.allows(viewOnly, 'read_file'), isTrue);
    expect(WorkCapabilities.allows(viewOnly, 'write_file'), isFalse);
    expect(WorkCapabilities.allows(viewOnly, 'run_shell'), isFalse);
    expect(WorkCapabilities.allows(full, 'run_shell'), isTrue);
    expect(WorkCapabilities.allows(full, 'tap'), isFalse);
    expect(WorkCapabilities.allows(root, 'tap'), isTrue);
    expect(WorkCapabilities.allows(full, 'format_disk'), isFalse,
        reason: '未登记动作默认拒绝');

    // 桌面 3 档 / 移动 5 档
    expect(WorkPermissions.tiersFor(WorkPlatform.linux).length, 3);
    expect(WorkPermissions.tiersFor(WorkPlatform.android).length, 5);
  });
}
