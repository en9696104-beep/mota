import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../services/ask_user_service.dart';
import '../theme/app_theme.dart';

/// Ask 技能问卷卡片：模型发起的结构化提问 → 用户作答/跳过
///
/// 交互对齐 DSH user-questions：
/// - 单选题（radio）/ 多选题（checkbox）/ 无选项自由回答（文本框）
/// - 「跳过全部」= 中止（上层回喂 ASK_ABORTED 错误码，模型自行决策）
class AskUserDialog extends StatefulWidget {
  const AskUserDialog({super.key, required this.questions});

  final List<AskQuestion> questions;

  /// 弹出问卷；用户直接关闭 / 跳过时返回 aborted
  static Future<AskOutcome> show(List<AskQuestion> questions) async {
    final outcome = await Get.dialog<AskOutcome>(
      AskUserDialog(questions: questions),
      barrierDismissible: false,
    );
    return outcome ?? const AskOutcome(aborted: true);
  }

  @override
  State<AskUserDialog> createState() => _AskUserDialogState();
}

class _AskUserDialogState extends State<AskUserDialog> {
  final _selected = <String, Set<String>>{};
  final _freeText = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    for (final q in widget.questions) {
      _selected[q.id] = <String>{};
      if (q.options.isEmpty) {
        _freeText[q.id] = TextEditingController();
      }
    }
  }

  @override
  void dispose() {
    for (final c in _freeText.values) {
      c.dispose();
    }
    super.dispose();
  }

  AskOutcome _collect() {
    final answers = <String, List<String>>{};
    for (final q in widget.questions) {
      final picked = _selected[q.id]!.where((s) => s.isNotEmpty).toList();
      final text = _freeText[q.id]?.text.trim();
      if (text != null && text.isNotEmpty) {
        picked.add(text);
      }
      answers[q.id] = picked;
    }
    final any = answers.values.any((v) => v.isNotEmpty);
    return AskOutcome(
      aborted: !any,
      answers: answers,
      questions: widget.questions,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.help_outline, size: 20, color: AppColors.accent),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '模型需要你的补充信息',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.55,
          maxWidth: 420,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < widget.questions.length; i++) ...[
                if (i > 0) const SizedBox(height: 16),
                _questionCard(widget.questions[i]),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Get.back<AskOutcome>(
            result: AskOutcome(aborted: true, questions: widget.questions),
          ),
          child: const Text(
            '跳过（不回答）',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ),
        TextButton(
          onPressed: () => Get.back<AskOutcome>(result: _collect()),
          child: const Text(
            '提交回答',
            style: TextStyle(
              color: AppColors.accent,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _questionCard(AskQuestion q) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            q.question,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          if (q.multiSelect)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text(
                '可多选',
                style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
              ),
            ),
          if (q.options.isEmpty) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _freeText[q.id],
              maxLines: 2,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
              ),
              decoration: const InputDecoration(
                hintText: '输入你的回答…',
                hintStyle: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 13,
                ),
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in q.options) _optionChip(q, option),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _optionChip(AskQuestion q, AskOption option) {
    final selected = _selected[q.id]!.contains(option.label);
    return FilterChip(
      selected: selected,
      label: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            option.label,
            style: TextStyle(
              color: selected ? AppColors.accent : AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (option.description != null &&
              option.description!.trim().isNotEmpty)
            Text(
              option.description!,
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 11,
              ),
            ),
        ],
      ),
      backgroundColor: AppColors.surface,
      checkmarkColor: AppColors.accent,
      onSelected: (value) {
        setState(() {
          if (value) {
            if (!q.multiSelect) _selected[q.id]!.clear();
            _selected[q.id]!.add(option.label);
          } else {
            _selected[q.id]!.remove(option.label);
          }
        });
      },
    );
  }
}
