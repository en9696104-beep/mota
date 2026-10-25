import 'package:flutter/material.dart';

import '../data/models/ai_model.dart';
import '../theme/format_theme.dart';

/// 模型架构小标签：显示在模型卡片上，颜色与筛选 Chip 一致
/// - GGUF 纯白 / MNN 科技蓝 / LiteRT 谷歌四色渐变 / Apple 钛金属灰
class FormatBadge extends StatelessWidget {
  const FormatBadge({super.key, required this.format, this.compact = false});

  final ModelFormat format;

  /// 紧凑模式：更小字号与内边距（用于卡片标题行）
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isLitert = format == ModelFormat.litert;
    final textColor = FormatTheme.textColorOf(format, selected: true);
    final gradient = FormatTheme.gradientOf(format);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 7,
        vertical: compact ? 1.5 : 2,
      ),
      decoration: BoxDecoration(
        gradient: isLitert ? gradient : null,
        color: isLitert ? null : FormatTheme.softOf(format),
        borderRadius: BorderRadius.circular(compact ? 5 : 6),
        border: Border.all(
          color: isLitert
              ? Colors.transparent
              : FormatTheme.colorOf(format).withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLitert) ...[
            Container(
              width: 5,
              height: 5,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFFFFFFF),
              ),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            format.label,
            style: TextStyle(
              color: textColor,
              fontSize: compact ? 9.5 : 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              shadows: isLitert
                  ? const [
                      Shadow(
                        color: Color(0x66000000),
                        offset: Offset(0, 1),
                        blurRadius: 2,
                      ),
                    ]
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
