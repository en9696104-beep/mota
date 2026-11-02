import 'package:flutter_test/flutter_test.dart';
import 'package:mota/services/mcp/tool_prompt.dart';

void main() {
  group('ToolCallParser 标准格式', () {
    test('标准 tool 围栏', () {
      const text = '让我查一下。\n```tool\n{"name": "get_weather", '
          '"arguments": {"city": "北京"}}\n```';
      final result = ToolCallParser.parseDetailed(text);
      expect(result.calls, hasLength(1));
      expect(result.calls.first.name, 'get_weather');
      expect(result.calls.first.arguments['city'], '北京');
      expect(result.error, isNull);
    });

    test('无工具调用意图时 error 为 null', () {
      final result = ToolCallParser.parseDetailed('今天天气不错，有什么可以帮你？');
      expect(result.calls, isEmpty);
      expect(result.hasAttempt, isFalse);
    });
  });

  group('ToolCallParser 小模型容错（核心）', () {
    test('尾逗号', () {
      const text = '```tool\n{"name": "f", "arguments": {"a": 1,}}\n```';
      expect(ToolCallParser.parseDetailed(text).calls.first.arguments['a'], 1);
    });

    test('单引号字符串', () {
      const text = "```tool\n{'name': 'f', 'arguments': {'a': '北京'}}\n```";
      final call = ToolCallParser.parseDetailed(text).calls.first;
      expect(call.name, 'f');
      expect(call.arguments['a'], '北京');
    });

    test('裸键名', () {
      const text = '```tool\n{name: "f", arguments: {city: "上海"}}\n```';
      final call = ToolCallParser.parseDetailed(text).calls.first;
      expect(call.name, 'f');
      expect(call.arguments['city'], '上海');
    });

    test('Python 字面量 True/False/None', () {
      const text =
          '```tool\n{"name": "f", "arguments": {"a": True, "b": False, "c": None}}\n```';
      final args = ToolCallParser.parseDetailed(text).calls.first.arguments;
      expect(args['a'], true);
      expect(args['b'], false);
      expect(args['c'], isNull);
    });

    test('全角标点', () {
      const text = '```tool\n｛"name"："f"，"arguments"：｛"a"：1｝｝\n```';
      expect(ToolCallParser.parseDetailed(text).calls, isNotEmpty);
    });

    test('```json 围栏别名', () {
      const text =
          '```json\n{"name": "f", "arguments": {"a": 1}}\n```';
      expect(ToolCallParser.parseDetailed(text).calls.first.name, 'f');
    });

    test('未闭合代码块（小模型忘写结尾 ```）', () {
      const text = '```tool\n{"name": "f", "arguments": {"a": 1}}';
      expect(ToolCallParser.parseDetailed(text).calls.first.name, 'f');
    });

    test('裸 JSON 对象（忘写围栏）', () {
      const text = '好的，我来调用：{"name": "f", "arguments": {"a": 1}}';
      expect(ToolCallParser.parseDetailed(text).calls.first.name, 'f');
    });

    test('字段别名 tool_name / args / parameters', () {
      const t1 = '```tool\n{"tool_name": "f", "args": {"a": 1}}\n```';
      const t2 = '```tool\n{"name": "f", "parameters": {"a": 1}}\n```';
      const t3 = '```tool\n{"tool": "f", "params": {"a": 1}}\n```';
      for (final t in [t1, t2, t3]) {
        final call = ToolCallParser.parseDetailed(t).calls.first;
        expect(call.name, 'f');
        expect(call.arguments['a'], 1);
      }
    });

    test('OpenAI 风格 function 嵌套', () {
      const text = '```tool\n{"function": {"name": "f", '
          '"arguments": "{\\"a\\": 1}"}}\n```';
      final call = ToolCallParser.parseDetailed(text).calls.first;
      expect(call.name, 'f');
      expect(call.arguments['a'], 1);
    });

    test('arguments 输出成 JSON 字符串', () {
      const text = '```tool\n{"name": "f", "arguments": "{\\"a\\": 1}"}\n```';
      expect(ToolCallParser.parseDetailed(text).calls.first.arguments['a'], 1);
    });

    test('普通代码块（dart 等）不误判', () {
      const text = '```dart\nvoid main() { print("hi"); }\n```';
      final result = ToolCallParser.parseDetailed(text);
      expect(result.calls, isEmpty);
      expect(result.hasAttempt, isFalse);
    });

    test('tool 围栏但 JSON 损坏 → 记为错误尝试', () {
      const text = '```tool\n{"name": "f", "arguments": {"a": }}}\n```';
      final result = ToolCallParser.parseDetailed(text);
      expect(result.calls, isEmpty);
      expect(result.hasAttempt, isTrue);
      expect(result.error, isNotNull);
    });

    test('围栏外说明文字被容忍', () {
      const text = '我需要查询天气。\n```tool\n'
          '{"name": "get_weather", "arguments": {"city": "北京"}}\n```\n'
          '请稍等。';
      expect(ToolCallParser.parseDetailed(text).calls, hasLength(1));
    });
  });

  group('ToolPrompt', () {
    test('提示词包含 one-shot 示例与硬性规则', () {
      final prompt = ToolPrompt.buildToolsPrompt(
        const [],
        extraToolLines: ['ask_user_question：向用户提问'],
      );
      expect(prompt, contains('```tool'));
      expect(prompt, contains('get_weather'));
      expect(prompt, contains('硬性规则'));
      expect(prompt, contains('ask_user_question'));
    });
  });
}
