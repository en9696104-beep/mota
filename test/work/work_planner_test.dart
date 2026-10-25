import 'package:flutter_test/flutter_test.dart';
import 'package:mota/work/models/work_permission.dart';
import 'package:mota/work/services/work_planner.dart';

/// LLM 拆解器的纯函数解析测试（不依赖模型加载）
void main() {
  group('WorkPlanner.parseSteps', () {
    test('标准 JSON 数组', () {
      final steps = WorkPlanner.parseSteps('''
[
  {"action": "device_info", "reason": "看设备", "target": "", "args": {}},
  {"action": "read_file", "reason": "读文件", "target": "/tmp/a.txt"}
]
''');
      expect(steps, isNotNull);
      expect(steps!.length, 2);
      expect(steps[0].action, 'device_info');
      expect(steps[1].target, '/tmp/a.txt');
    });

    test('容忍 markdown 代码围栏', () {
      final steps = WorkPlanner.parseSteps('''
好的，我来拆解：
```json
[{"action": "list_files", "reason": "列目录", "target": "/tmp"}]
```
''');
      expect(steps, isNotNull);
      expect(steps!.single.action, 'list_files');
    });

    test('容忍 JSON 前后的解释文字', () {
      final steps = WorkPlanner.parseSteps(
          '我先看一下步骤：[{"action":"run_shell","reason":"看磁盘","target":"df -h"}] 完成');
      expect(steps, isNotNull);
      expect(steps!.single.target, 'df -h');
    });

    test('过滤未登记动作（护栏第二道防线前的第一道）', () {
      final steps = WorkPlanner.parseSteps('''
[
  {"action": "format_disk", "reason": "危险", "target": "/dev/sda"},
  {"action": "device_info", "reason": "安全"}
]
''');
      expect(steps, isNotNull);
      expect(steps!.length, 1);
      expect(steps.single.action, 'device_info');
    });

    test('缺 reason 时给默认理由', () {
      final steps = WorkPlanner.parseSteps(
          '[{"action": "device_info"}]');
      expect(steps, isNotNull);
      expect(steps!.single.reason, '模型规划步骤');
    });

    test('args 透传', () {
      final steps = WorkPlanner.parseSteps(
          '[{"action": "write_file", "reason": "写", "target": "/tmp/b.txt", "args": {"content": "hello"}}]');
      expect(steps, isNotNull);
      expect(steps!.single.args['content'], 'hello');
    });

    test('完全无法解析返回 null', () {
      expect(WorkPlanner.parseSteps(''), isNull);
      expect(WorkPlanner.parseSteps('我不知道怎么拆解'), isNull);
      expect(WorkPlanner.parseSteps('[这不是合法json'), isNull);
      expect(WorkPlanner.parseSteps('{"action": "device_info"}'), isNull,
          reason: '顶层不是数组');
    });

    test('全部动作未登记时返回空列表而非 null', () {
      final steps = WorkPlanner.parseSteps('[{"action": "hack", "reason": "x"}]');
      expect(steps, isNotNull);
      expect(steps, isEmpty);
    });
  });

  group('prompt 与目录', () {
    test('系统提示词包含全部已登记动作', () {
      final prompt = WorkPlanner.systemPrompt;
      for (final action in <String>[
        'device_info',
        'list_files',
        'read_file',
        'write_file',
        'delete_file',
        'run_shell',
      ]) {
        expect(prompt, contains(action));
      }
    });

    test('动作中文标签覆盖全部登记动作', () {
      for (final action in WorkPlanner.actionLabels.keys) {
        expect(WorkPlanner.labelOf(action), isNotEmpty);
      }
      // 未登记动作回落原名
      expect(WorkPlanner.labelOf('mystery'), 'mystery');
    });

    test('桌面平台不暴露移动专有动作', () {
      final desktop = WorkPlanner.actionsForPlatform(WorkPlatform.linux);
      expect(desktop, contains('run_shell'));
      expect(desktop, isNot(contains('tap')));
      final android = WorkPlanner.actionsForPlatform(WorkPlatform.android);
      expect(android, contains('tap'));
    });
  });
}
