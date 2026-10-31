import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/history_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/history_tile.dart';

/// Tab 3：历史对话（与各模型的聊天记录列表）
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<HistoryController>();
    return Scaffold(
      appBar: AppBar(
        title: Text('历史对话'.tr),
        actions: [
          Obx(
            () => Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '@n 条记录'
                      .trParams({'n': '${controller.sessions.length}'}),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Obx(() {
        if (controller.loading.value) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.accent),
          );
        }
        if (controller.sessions.isEmpty) {
          return const EmptyState(
            icon: Icons.chat_bubble_outline,
            title: '暂无对话记录',
            subtitle: '在「我的模型」中开始一次对话，记录会出现在这里',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: controller.sessions.length,
          separatorBuilder: (_, __) => Container(
            height: 1,
            color: AppColors.border,
            margin: const EdgeInsets.only(left: 56),
          ),
          itemBuilder: (_, index) {
            final session = controller.sessions[index];
            return HistoryTile(
              session: session,
              onTap: () => controller.openSession(session),
              onDelete: () => controller.deleteSession(session.id),
            );
          },
        );
      }),
    );
  }
}
