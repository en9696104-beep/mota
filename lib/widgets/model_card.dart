import 'package:flutter/material.dart';

import '../data/models/ai_model.dart';
import '../theme/app_theme.dart';
import 'download_button.dart';
import 'format_badge.dart';
import 'model_avatar.dart';
import 'tag_chip.dart';

/// 商店页模型卡片：头像 + 名称 + 体积 + 元信息 + 标签 + 下载按钮
class ModelCard extends StatelessWidget {
  const ModelCard({super.key, required this.model});

  final AiModel model;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ModelAvatar(name: model.name, colorIndex: model.colorIndex),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        model.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizeBadge(model.sizeLabel),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    // 架构标签（GGUF 纯白 / MNN 蓝 / LiteRT 渐变 / Apple 钛灰）
                    FormatBadge(format: model.format, compact: true),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${model.author} · ${model.params} · ${model.quant}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // GitHub 热度（启动时异步刷新）
                    const Icon(
                      Icons.star_rounded,
                      size: 12,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      _formatStars(model.githubStars),
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: model.tags.map((t) => TagChip(t)).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: DownloadButton(model: model),
          ),
        ],
      ),
    );
  }

  /// 星数紧凑展示：12345 -> 12.3k
  static String _formatStars(int stars) {
    if (stars >= 1000) {
      return '${(stars / 1000).toStringAsFixed(1)}k';
    }
    return '$stars';
  }
}
