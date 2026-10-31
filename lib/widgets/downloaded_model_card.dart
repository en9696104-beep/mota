import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/my_models_controller.dart';
import '../data/models/ai_model.dart';
import '../routes/app_routes.dart';
import '../theme/app_theme.dart';
import '../theme/format_theme.dart';
import 'format_badge.dart';
import 'model_avatar.dart';
import 'tag_chip.dart';

/// 「我的模型」网格卡片：头像 + 体积 + 名称 + 元信息 + 标签 + 操作按钮
/// 整卡点击进入对话（携带本地 GGUF 路径）
class DownloadedModelCard extends StatelessWidget {
  const DownloadedModelCard({super.key, required this.model});

  final AiModel model;

  /// 进入对话页：按架构路由——GGUF 走 llama.cpp 引擎；
  /// MNN / LiteRT / Apple 引擎适配中，弹优雅提示并阻止进入，防止闪退
  void _openChat() {
    if (model.format != ModelFormat.gguf) {
      _showEnginePendingToast(model.format);
      return;
    }
    final controller = Get.find<MyModelsController>();
    final path = controller.pathFor(model.id);
    Get.toNamed(
      AppRoutes.chat,
      arguments: <String, dynamic>{
        'modelId': model.id,
        'modelName': model.name,
        if (path != null) 'modelPath': path,
      },
    );
  }

  /// 引擎适配中的优雅提示：带架构配色的悬浮 Toast（非侵入，自动消失）
  void _showEnginePendingToast(ModelFormat format) {
    Get.snackbar(
      '',
      '',
      titleText: const SizedBox.shrink(),
      messageText: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: FormatTheme.colorOf(format).withValues(alpha: 0.55),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FormatBadge(format: format),
            const SizedBox(width: 10),
            const Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '该架构引擎正在适配中，敬请期待',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'GGUF 模型可直接对话；其他架构可正常管理文件',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.hourglass_bottom_rounded,
              size: 16,
              color: FormatTheme.colorOf(format),
            ),
          ],
        ),
      ),
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.transparent,
      boxShadows: [],
      borderRadius: 12,
      margin: const EdgeInsets.all(20),
      duration: const Duration(seconds: 3),
      isDismissible: true,
      animationDuration: const Duration(milliseconds: 280),
      forwardAnimationCurve: Curves.easeOutBack,
    );
  }

  /// 删除前二次确认：模型文件动辄数 GB，防止误触
  Future<void> _confirmDelete() async {
    final controller = Get.find<MyModelsController>();
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          '删除模型',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          '确定要删除该模型文件以释放空间吗？\n\n${model.name}（${model.sizeLabel}）将从本机移除，如需使用需重新下载。',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text(
              '取消',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            child: const Text(
              '删除',
              style: TextStyle(
                color: AppColors.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await controller.removeModel(model.id);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _openChat,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ModelAvatar(
                  name: model.name,
                  colorIndex: model.colorIndex,
                  author: model.author,
                  size: 38,
                ),
                const Spacer(),
                SizeBadge(model.sizeLabel),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              model.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                // 架构标签（GGUF 纯白 / MNN 蓝 / LiteRT 渐变 / Apple 钛灰）
                FormatBadge(format: model.format, compact: true),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${model.params} · ${model.quant} · 已就绪',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: model.tags.take(2).map((t) => TagChip(t)).toList(),
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _openChat,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '开始对话',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _confirmDelete,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Icon(
                      Icons.delete_outline,
                      color: AppColors.textSecondary,
                      size: 17,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
