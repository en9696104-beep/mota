import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mota/widgets/model_name_text.dart';

void main() {
  /// 目录中最长的内置模型名（38 字符），此前必被 "…" 截断
  const longest = 'DeepSeek-R1-Distill-Qwen-32B (unsloth)';

  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  group('ModelNameText：模型名完整展示契约', () {
    testWidgets('长名称原样渲染，且绝不设置 ellipsis', (tester) async {
      await tester.pumpWidget(wrap(const ModelNameText(longest)));

      final text = tester.widget<Text>(find.text(longest));
      expect(text.data, longest, reason: '名称不应被改写或截断');
      expect(
        text.overflow,
        isNot(TextOverflow.ellipsis),
        reason: '禁用省略号是本次修复的核心契约',
      );
      expect(text.overflow, TextOverflow.clip);
      expect(text.maxLines, 3);
    });

    testWidgets('默认带 Tooltip 兜底，内容为完整名称', (tester) async {
      await tester.pumpWidget(wrap(const ModelNameText(longest)));

      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, longest);
    });

    testWidgets('可关闭 Tooltip、可配置 maxLines（AppBar 单行 + FittedBox）', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const ModelNameText(longest, maxLines: 1, tooltip: false)),
      );

      expect(find.byType(Tooltip), findsNothing);
      final text = tester.widget<Text>(find.text(longest));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.clip);
    });

    testWidgets('maxLines: null 时完全不限行（商店列表场景）', (tester) async {
      await tester.pumpWidget(
        wrap(const ModelNameText(longest, maxLines: null)),
      );

      final text = tester.widget<Text>(find.text(longest));
      expect(text.maxLines, isNull);
      expect(text.overflow, isNot(TextOverflow.ellipsis));
    });

    testWidgets('空名称不挂 Tooltip 也不报错', (tester) async {
      await tester.pumpWidget(wrap(const ModelNameText('')));
      expect(tester.takeException(), isNull);
      expect(find.byType(Tooltip), findsNothing);
    });
  });
}
