import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mota/widgets/model_name_text.dart';
import 'package:mota/widgets/tag_chip.dart';

/// 商店卡片标题行在窄屏 + 长体积文案下，模型名不得被挤成逐字竖排（"蛋挞"）。
///
/// 复现场景：模型带投影器时 sizeLabel 形如
/// "3.85 GB + 投影器 811 MB"，此前 SizeBadge 无宽度约束、名称用裸 Expanded，
/// 结果体积徽标横向撑开把名称列挤到不足一个字符宽，maxLines:null 逐字换行。
/// 此处直接复刻修复后的标题行布局（不依赖 DownloadButton / GetX），
/// 精准验证名称列与体积徽标的宽度分配。
void main() {
  const longName = 'Gemma 3-4B (ggm官方)';
  const longSize = '3.85 GB + 投影器 811 MB';

  /// 与 model_card.dart 标题行完全一致的布局结构
  Widget titleRow() => const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            // 固定高度 + 窄宽：标题行在卡片中实际可用宽度约 200px
            width: 200,
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: ModelNameText(longName, maxLines: null),
                ),
                SizedBox(width: 8),
                Flexible(flex: 2, fit: FlexFit.loose, child: SizeBadge(longSize)),
              ],
            ),
          ),
        ),
      );

  testWidgets('长体积文案下模型名列仍有足够宽度，不逐字竖排', (tester) async {
    await tester.pumpWidget(titleRow());

    final nameBox = tester.renderObject<RenderBox>(find.byType(ModelNameText));
    final nameWidth = nameBox.size.width;

    // 名称列宽度必须足以容纳多个字符并排（此前会被挤到 < 20px 而竖排）
    expect(
      nameWidth,
      greaterThan(90),
      reason: '模型名列被体积徽标挤压到 $nameWidth px，会逐字竖排成"蛋挞"',
    );
  });

  testWidgets('体积徽标限制行数，长文案折行且不显示省略号', (tester) async {
    await tester.pumpWidget(titleRow());

    final badge = tester.widget<SizeBadge>(find.byType(SizeBadge));
    expect(badge.maxLines, 2, reason: '体积徽标须限制行数以便折行');
    final text = tester.widget<Text>(find.descendant(
      of: find.byType(SizeBadge),
      matching: find.byType(Text),
    ));
    expect(text.maxLines, 2);
    expect(text.overflow, isNot(TextOverflow.ellipsis));
  });
}
