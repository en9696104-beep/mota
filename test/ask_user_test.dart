import 'package:flutter_test/flutter_test.dart';
import 'package:mota/services/ask_user_service.dart';

void main() {
  group('AskToolHandler.normalize', () {
    test('标准结构化问题', () {
      final r = AskToolHandler.normalize(<String, dynamic>{
        'questions': [
          {
            'question': '用哪种风格？',
            'options': [
              {'label': '简洁', 'description': '一句话'},
              {'label': '详细'},
            ],
            'multiSelect': false,
          },
        ],
      });
      expect(r.error, isNull);
      expect(r.questions, hasLength(1));
      expect(r.questions.first.options, hasLength(2));
      expect(r.questions.first.options.first.description, '一句话');
      expect(r.questions.first.multiSelect, isFalse);
    });

    test('字符串选项与字符串问题（便捷形式）', () {
      final r1 = AskToolHandler.normalize(<String, dynamic>{
        'questions': [
          {'question': '选一个', 'options': ['甲', '乙']},
        ],
      });
      expect(r1.questions.first.options.map((o) => o.label), ['甲', '乙']);

      final r2 = AskToolHandler.normalize(<String, dynamic>{'question': '直接问'});
      expect(r2.questions.first.question, '直接问');
      expect(r2.questions.first.options, isEmpty);
    });

    test('字段别名 text / multiple', () {
      final r = AskToolHandler.normalize(<String, dynamic>{
        'questions': [
          {'text': '问什么', 'multiple': true, 'options': ['a', 'b']},
        ],
      });
      expect(r.questions.first.question, '问什么');
      expect(r.questions.first.multiSelect, isTrue);
    });

    test('最多 3 个问题', () {
      final r = AskToolHandler.normalize(<String, dynamic>{
        'questions': [
          {'question': 'q1'},
          {'question': 'q2'},
          {'question': 'q3'},
          {'question': 'q4'},
        ],
      });
      expect(r.questions, hasLength(3));
    });

    test('缺少 questions → 错误信息含示例', () {
      final r = AskToolHandler.normalize(<String, dynamic>{});
      expect(r.error, isNotNull);
      expect(r.error, contains('questions'));
    });

    test('问题缺 question 文本 → 报错', () {
      final r = AskToolHandler.normalize(<String, dynamic>{
        'questions': [
          {'options': ['a']},
        ],
      });
      expect(r.error, isNotNull);
    });
  });

  group('AskOutcome.feedback（对齐 DSH 错误码语义）', () {
    test('正常回答 → 按问题回显答案', () {
      const outcome = AskOutcome(
        aborted: false,
        answers: {'q1': ['简洁']},
        questions: [
          AskQuestion(
            id: 'q1',
            question: '用哪种风格？',
            options: [AskOption(label: '简洁')],
          ),
        ],
      );
      final feedback = outcome.feedback;
      expect(feedback, contains('用户已回答你的问题'));
      expect(feedback, contains('用哪种风格？'));
      expect(feedback, contains('简洁'));
      expect(feedback, isNot(contains('ASK_ABORTED')));
    });

    test('中止 → ASK_ABORTED 错误码', () {
      const outcome = AskOutcome(aborted: true);
      expect(outcome.feedback, contains('ASK_ABORTED'));
    });

    test('回答但全空 → ASK_ABORTED', () {
      const outcome = AskOutcome(
        aborted: false,
        answers: {'q1': <String>[]},
        questions: [AskQuestion(id: 'q1', question: 'q')],
      );
      expect(outcome.feedback, contains('ASK_ABORTED'));
    });

    test('多选题答案用顿号连接', () {
      const outcome = AskOutcome(
        aborted: false,
        answers: {'q1': ['甲', '乙']},
        questions: [AskQuestion(id: 'q1', question: '要哪些？', multiSelect: true)],
      );
      expect(outcome.feedback, contains('甲、乙'));
    });
  });
}
