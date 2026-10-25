import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/store_controller.dart';
import '../routes/app_routes.dart';
import '../theme/app_theme.dart';
import '../widgets/filter_panel.dart';
import '../widgets/model_card.dart';

/// Tab 2：模型商店（多维度筛选 + 模型卡片列表）
class StorePage extends StatelessWidget {
  const StorePage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<StoreController>();
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('模型商店'),
            SizedBox(height: 2),
            Text(
              'GGUF 格式 · 下载后完全离线运行',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
        actions: [
          // 设置（检查更新 / 商店数据来源）
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 20),
            tooltip: '设置',
            color: AppColors.textSecondary,
            onPressed: () => Get.toNamed(AppRoutes.settings),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 多维度筛选面板（替代原四个分类标签）
          const FilterPanel(),
          // 结果统计 + 排序下拉
          Obx(
            () => Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      controller.activeFilterCount == 0
                          ? '全部 ${controller.models.length} 个模型'
                          : '筛选出 ${controller.models.length} 个模型',
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                  // 排序切换：热度（默认）/ 大小 / 名称
                  PopupMenuButton<SortMode>(
                    initialValue: controller.sortBy.value,
                    color: AppColors.surfaceHigh,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: AppColors.border),
                    ),
                    onSelected: controller.setSortBy,
                    itemBuilder: (_) => SortMode.values
                        .map((m) => PopupMenuItem<SortMode>(
                              value: m,
                              height: 38,
                              child: Row(
                                children: [
                                  Icon(
                                    controller.sortBy.value == m
                                        ? Icons.check
                                        : Icons.arrow_drop_down,
                                    size: 15,
                                    color: controller.sortBy.value == m
                                        ? AppColors.accent
                                        : Colors.transparent,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    m.label,
                                    style: TextStyle(
                                      color: controller.sortBy.value == m
                                          ? AppColors.accent
                                          : AppColors.textSecondary,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceHigh,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.sort,
                            size: 13,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: 5),
                          Obx(
                            () => Text(
                              controller.sortBy.value.label,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.arrow_drop_down,
                            size: 15,
                            color: AppColors.textTertiary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 模型卡片列表
          Expanded(
            child: Obx(
              () => controller.models.isEmpty
                  ? _EmptyResult(
                      hasFilter: controller.activeFilterCount > 0,
                      onClear: controller.clearFilters,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: controller.models.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, index) =>
                          ModelCard(model: controller.models[index]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyResult extends StatelessWidget {
  const _EmptyResult({required this.hasFilter, required this.onClear});

  final bool hasFilter;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.filter_alt_off,
              size: 40,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 12),
            Text(
              hasFilter ? '没有符合筛选条件的模型' : '商店暂无数据',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            if (hasFilter) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: onClear,
                child: const Text(
                  '清空筛选条件',
                  style: TextStyle(color: AppColors.accent),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
