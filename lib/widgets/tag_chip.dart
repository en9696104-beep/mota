import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 灰色小标签，如 [中文] [Q4_K_M]
class TagChip extends StatelessWidget {
  const TagChip(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        label,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 10.5),
      ),
    );
  }
}

/// 体积徽标，如 4.4 GB
///
/// [maxLines] 限制文案行数（默认 2）：带投影器的模型文案较长
/// （如 "3.85 GB + 投影器 811 MB"），若不换行会在 Row 里横向撑开，
/// 把相邻的模型名列挤到只剩一个字符宽而逐字竖排。收进 [Flexible] 后
/// 本组件靠此参数折行，保证名称列有足够宽度。
class SizeBadge extends StatelessWidget {
  const SizeBadge(this.label, {super.key, this.maxLines = 2});

  final String label;

  /// 最多行数；设为 1 可保持单行（仅用于宽度充裕的场景）
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Tooltip(
        message: label,
        waitDuration: const Duration(milliseconds: 350),
        child: Text(
          label,
          maxLines: maxLines,
          overflow: TextOverflow.clip,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
