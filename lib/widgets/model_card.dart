import 'package:flutter/material.dart';

import '../data/models/ai_model.dart';
import '../theme/app_theme.dart';
import 'download_button.dart';
import 'format_badge.dart';
import 'model_avatar.dart';
import 'model_name_text.dart';
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
          ModelAvatar(
            name: model.name,
            colorIndex: model.colorIndex,
            author: model.author,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 名称占大头；体积徽标用 Flexible 收进剩余空间，
                    // 避免长文案（带投影器）把名称挤成逐字竖排
                    Expanded(
                      flex: 3,
                      child: ModelNameText(
                        model.name,
                        // 商店列表无固定高度：不限行数，完整换行展示
                        maxLines: null,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      flex: 2,
                      fit: FlexFit.loose,
                      child: SizeBadge(model.sizeLabel),
                    ),
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
                        maxLines: 2,
                        overflow: TextOverflow.clip,
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
                // 标签限行：窄屏下最多展示 6 个，防止卡片被撑得过长
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    ...model.tags.take(6).map((t) => TagChip(t)),
                    if (model.tags.length > 6)
                      TagChip('+${model.tags.length - 6}'),
                  ],
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
