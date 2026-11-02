import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ask 技能：对齐 DeepSeek Harness（DSH）的人机问答接缝
/// （packages/interaction/user-questions）。
///
/// 模型在任务进行中可通过内置工具 ask_user_question 向用户发出
/// 结构化问题（问题 + 选项 + 多选标记），UI 弹出问卷卡片收集答案，
/// 答案作为工具结果回喂模型；用户可中止（返回稳定错误码 ASK_ABORTED，
/// 模型据此决定重试、放弃或换路推进）。
class AskOption {
  const AskOption({required this.label, this.description});

  final String label;

  /// 选项补充说明（UI 次行展示，可为空）
  final String? description;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'label': label,
    if (description != null) 'description': description,
  };
}

/// 一个待用户回答的问题
class AskQuestion {
  const AskQuestion({
    required this.id,
    required this.question,
    this.options = const <AskOption>[],
    this.multiSelect = false,
  });

  /// 稳定 id（答案按 id 路由，对齐 DSH 的批量答案路由设计）
  final String id;
  final String question;
  final List<AskOption> options;

  /// true = 可多选（checkbox），false = 单选/自由回答
  final bool multiSelect;
}

/// 问卷结果：aborted（用户中止）或按问题 id 给出的答案
class AskOutcome {
  const AskOutcome({
    required this.aborted,
    this.answers = const <String, List<String>>{},
    this.questions = const <AskQuestion>[],
  });

  final bool aborted;
  final Map<String, List<String>> answers;
  final List<AskQuestion> questions;

  /// 工具结果文本（回喂模型）
  String get feedback {
    if (aborted) {
      return '错误码 ASK_ABORTED：用户未回答本次提问。'
          '请基于已有信息直接推进任务或给出答案，不要再次重复提问。';
    }
    final hasAnyAnswer = answers.values.any((v) => v.isNotEmpty);
    if (!hasAnyAnswer) {
      return '错误码 ASK_ABORTED：用户未提供任何回答。'
          '请基于已有信息直接推进任务。';
    }
    final buffer = StringBuffer('用户已回答你的问题：');
    for (final q in questions) {
      final labels = answers[q.id];
      if (labels == null) continue;
      buffer
        ..writeln()
        ..write(
          '问：${q.question}\n答：${labels.isEmpty ? '（未选择，跳过）' : labels.join('、')}',
        );
    }
    return buffer.toString();
  }
}

/// 从工具调用参数规范化出问题列表（容错：字段别名、字符串选项）
class AskToolHandler {
  AskToolHandler._();

  static const Set<String> names = <String>{
    'ask_user_question',
    'ask_user',
    'ask',
  };

  /// 工具描述行（注入工具提示词）
  static String get promptLine =>
      'ask_user_question：任务进行中需要用户补充信息时，向用户提出结构化问题。'
      '参数 {"questions": [{"question": "问题", '
      '"options": [{"label": "选项", "description": "说明"}], "multiSelect": false}]}，'
      '一次最多 3 个问题；用户可能拒绝回答（ASK_ABORTED），届时请直接推进。';

  /// 解析 arguments.questions；不合法时返回 null 并给出 [error]
  static ({List<AskQuestion> questions, String? error}) normalize(
    Map<String, dynamic> arguments,
  ) {
    final raw = arguments['questions'] ?? arguments['question'];
    if (raw is String && raw.trim().isNotEmpty) {
      // 便捷形式：单个纯文本问题（无选项）
      return (
        questions: [AskQuestion(id: 'q1', question: raw.trim())],
        error: null,
      );
    }
    if (raw is! List || raw.isEmpty) {
      return (
        questions: const <AskQuestion>[],
        error:
            '缺少 questions 数组，'
            '示例：{"questions": [{"question": "用哪个风格？", '
            '"options": [{"label": "简洁"}, {"label": "详细"}]}]}',
      );
    }

    final questions = <AskQuestion>[];
    for (var i = 0; i < raw.length && i < 3; i++) {
      final item = raw[i];
      if (item is String) {
        if (item.trim().isEmpty) continue;
        questions.add(AskQuestion(id: 'q${i + 1}', question: item.trim()));
        continue;
      }
      if (item is! Map) {
        return (questions: questions, error: '第 ${i + 1} 个问题不是对象或字符串');
      }
      final text =
          (item['question'] ?? item['text'] ?? item['q'])?.toString().trim() ??
          '';
      if (text.isEmpty) {
        return (questions: questions, error: '第 ${i + 1} 个问题缺少 question 文本');
      }
      final options = <AskOption>[];
      final rawOptions = item['options'];
      if (rawOptions is List) {
        for (final opt in rawOptions) {
          if (opt is String && opt.trim().isNotEmpty) {
            options.add(AskOption(label: opt.trim()));
          } else if (opt is Map) {
            final label =
                (opt['label'] ?? opt['name'] ?? opt['value'])
                    ?.toString()
                    .trim() ??
                '';
            if (label.isEmpty) continue;
            options.add(
              AskOption(
                label: label,
                description: opt['description']?.toString(),
              ),
            );
          }
        }
      }
      questions.add(
        AskQuestion(
          id: (item['id'] ?? 'q${i + 1}').toString(),
          question: text,
          options: options,
          multiSelect: item['multiSelect'] == true || item['multiple'] == true,
        ),
      );
    }
    if (questions.isEmpty) {
      return (questions: questions, error: 'questions 为空');
    }
    return (questions: questions, error: null);
  }
}

/// Ask 技能开关（持久化；默认开启）
class AskUserService extends GetxService {
  AskUserService._();

  static final AskUserService instance = AskUserService._();

  static AskUserService get to => Get.find();

  static const String _prefsKey = 'ask_user_enabled_v1';

  /// 是否允许模型向用户提问
  final enabled = true.obs;

  SharedPreferences? _prefs;

  Future<AskUserService> init() async {
    _prefs = await SharedPreferences.getInstance();
    enabled.value = _prefs?.getBool(_prefsKey) ?? true;
    return this;
  }

  Future<void> setEnabled(bool value) async {
    enabled.value = value;
    await _prefs?.setBool(_prefsKey, value);
  }
}
