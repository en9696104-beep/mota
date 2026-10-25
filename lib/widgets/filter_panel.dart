import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/store_controller.dart';
import '../data/models/ai_model.dart';
import '../theme/app_theme.dart';
import '../theme/format_theme.dart';

/// 多维度筛选面板：大小 / 厂商 / 领域 / 垂直 / 协议
/// 维度之间 AND，维度内部 OR（多选组合过滤）
class FilterPanel extends StatelessWidget {
  const FilterPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<StoreController>();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部：展开/收起 + 激活条件数 + 清空
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: controller.togglePanel,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                children: [
                  const Icon(Icons.tune, size: 16, color: AppColors.accent),
                  const SizedBox(width: 8),
                  const Text(
                    '多维度筛选',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Obx(() {
                    final n = controller.activeFilterCount;
                    if (n == 0) {
                      return const Text(
                        '未筛选',
                        style: TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 11.5,
                        ),
                      );
                    }
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accentSoft,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$n 个条件',
                        style: const TextStyle(
                          color: AppColors.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }),
                  const Spacer(),
                  // 清空
                  Obx(() {
                    if (controller.activeFilterCount == 0) {
                      return const SizedBox.shrink();
                    }
                    return GestureDetector(
                      onTap: controller.clearFilters,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          '清空',
                          style: TextStyle(
                            color: AppColors.accent,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    );
                  }),
                  Obx(
                    () => AnimatedRotation(
                      turns: controller.panelExpanded.value ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: const Icon(
                        Icons.expand_more,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 展开的维度区
          Obx(
            () => AnimatedCrossFade(
              duration: const Duration(milliseconds: 180),
              crossFadeState: controller.panelExpanded.value
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              firstChild: _DimensionSections(controller: controller),
              secondChild: const SizedBox(width: double.infinity),
            ),
          ),
        ],
      ),
    );
  }
}

class _DimensionSections extends StatelessWidget {
  const _DimensionSections({required this.controller});

  final StoreController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 10),
          // 架构维度：专属极客配色 Chip（置顶，最基础的筛选维度）
          const _FormatDimensionTitle(),
          _DimensionTitle(
            title: '大小',
            options: SizeBucket.values.map((b) => b.label).toList(),
            selected: controller.selectedSizes.map((b) => b.label).toList(),
            onToggle: (label) {
              final bucket = SizeBucket.values.firstWhere((b) => b.label == label);
              controller.toggleSize(bucket);
            },
          ),
          _DimensionTitle(
            title: '领域',
            options: StoreController.domainOptions,
            selected: controller.selectedDomains.toList(),
            onToggle: controller.toggleDomain,
          ),
          _DimensionTitle(
            title: '垂直',
            options: controller.verticalOptions,
            selected: controller.selectedVerticals.toList(),
            onToggle: controller.toggleVertical,
          ),
          _DimensionTitle(
            title: '厂商',
            options: controller.vendorOptions,
            selected: controller.selectedVendors.toList(),
            onToggle: controller.toggleVendor,
          ),
          _DimensionTitle(
            title: '协议',
            options: controller.licenseOptions,
            selected: controller.selectedLicenses.toList(),
            onToggle: controller.toggleLicense,
          ),
        ],
      ),
    );
  }
}

class _DimensionTitle extends StatelessWidget {
  const _DimensionTitle({
    required this.title,
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  final String title;
  final List<String> options;
  final List<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: options.map((opt) {
              final isSelected = selected.contains(opt);
              return GestureDetector(
                onTap: () => onToggle(opt),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.accentSoft
                        : AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.accent
                          : Colors.transparent,
                    ),
                  ),
                  child: Text(
                    opt,
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.accent
                          : AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

/// 架构维度标题行 + 专属配色 Chip 行
/// - GGUF 纯白 / MNN 科技蓝 / LiteRT 谷歌四色渐变 / Apple 钛金属灰
class _FormatDimensionTitle extends StatelessWidget {
  const _FormatDimensionTitle();

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<StoreController>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '架构',
            style: TextStyle(
              color: AppColors.textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Obx(() {
            final selected = controller.selectedFormats;
            return Wrap(
              spacing: 6,
              runSpacing: 6,
              children: ModelFormat.values.map((format) {
                final isSelected = selected.contains(format);
                return GestureDetector(
                  onTap: () => controller.toggleFormat(format),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      // LiteRT 选中时直接铺渐变底色；其余用半透明主色
                      gradient: (format == ModelFormat.litert && isSelected)
                          ? FormatTheme.gradientOf(format)
                          : null,
                      color: format == ModelFormat.litert
                          ? (isSelected
                                ? null
                                : FormatTheme.softOf(format))
                          : (isSelected
                                ? FormatTheme.selectedOf(format)
                                : FormatTheme.softOf(format)),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? FormatTheme.colorOf(format)
                            : FormatTheme.colorOf(format).withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (format == ModelFormat.litert && isSelected) ...[
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
                            color: FormatTheme.textColorOf(
                              format,
                              selected: isSelected,
                            ),
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          }),
        ],
      ),
    );
  }
}
