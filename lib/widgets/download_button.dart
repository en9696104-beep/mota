import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/main_controller.dart';
import '../controllers/store_controller.dart';
import '../data/models/ai_model.dart';
import '../theme/app_theme.dart';

/// 商店卡片右侧按钮：下载 / 下载进度（可取消）/ 打开
class DownloadButton extends StatelessWidget {
  const DownloadButton({super.key, required this.model});

  final AiModel model;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<StoreController>();
    return Obx(() {
      if (controller.isDownloaded(model.id)) {
        return _StoreButton(
          label: '打开'.tr,
          filled: false,
          onTap: () => Get.find<MainController>().changeTab(0),
        );
      }
      final progress = controller.progress[model.id];
      if (progress != null) {
        // 下载中：显示真实进度，点击取消
        return GestureDetector(
          onTap: () => controller.cancelDownload(model.id),
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 72,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${(progress * 100).toInt()}%',
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 3,
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: AppColors.border,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return _StoreButton(
        label: '下载'.tr,
        filled: true,
        onTap: () => controller.pickSourceAndDownload(model),
      );
    });
  }
}

/// 下载 / 打开 小按钮
class _StoreButton extends StatelessWidget {
  const _StoreButton({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 64,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? AppColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: filled ? AppColors.accent : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: filled ? Colors.black : AppColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
