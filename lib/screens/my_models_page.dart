import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/main_controller.dart';
import '../controllers/my_models_controller.dart';
import '../screens/cooperation_page.dart';
import '../screens/group_chat_page.dart';
import '../services/model_import_service.dart';
import '../theme/app_theme.dart';
import '../widgets/downloaded_model_card.dart';
import '../widgets/empty_state.dart';

/// Tab 1：我的模型（本地已下载模型 + 自定义导入，网格布局）
class MyModelsPage extends StatefulWidget {
  const MyModelsPage({super.key});

  @override
  State<MyModelsPage> createState() => _MyModelsPageState();
}

class _MyModelsPageState extends State<MyModelsPage> {
  final _importService = ModelImportService.instance;
  bool _importing = false;

  /// 导入本地模型：文件选择 → 架构选择 → 落库
  Future<void> _importModel() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final model = await _importService.pickAndImport();
      if (!mounted) return;
      if (model != null) {
        Get.snackbar(
          '导入成功'.tr,
          '@name（@f）已加入我的模型'.trParams(
            {'name': model.name, 'f': model.format.label},
          ),
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } catch (e) {
      if (!mounted) return;
      Get.snackbar(
        '导入失败'.tr,
        e.toString().replaceFirst('Exception: ', ''),
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<MyModelsController>();
    return Scaffold(
      appBar: AppBar(
        title: Text('我的模型'.tr),
        actions: [
          // 群聊（多 AI 串行对话）
          IconButton(
            icon: const Icon(Icons.forum_outlined, size: 20),
            tooltip: '群聊（多 AI 对话）',
            onPressed: () => Get.to(() => const GroupChatPage()),
          ),
          // 合作系统（多模型接力管线）
          IconButton(
            icon: const Icon(Icons.account_tree_outlined, size: 20),
            tooltip: '合作系统',
            onPressed: () => Get.to(() => const CooperationPage()),
          ),
          // 导入本地模型（+ 号）
          _importing
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.add, size: 22),
                  tooltip: '导入本地模型',
                  onPressed: _importModel,
                ),
          Obx(
            () => Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '${controller.models.length} 个模型',
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
        // 空状态：引导去商店下载或导入本地模型
        if (controller.models.isEmpty) {
          return EmptyState(
            icon: Icons.memory_outlined,
            title: '还没有本地模型',
            subtitle: '去模型商店下载 GGUF 模型，或点击右上角 + 导入本地模型文件',
            actionLabel: '去商店逛逛',
            onAction: () => Get.find<MainController>().changeTab(1),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.95,
          ),
          itemCount: controller.models.length,
          itemBuilder: (_, index) =>
              DownloadedModelCard(model: controller.models[index]),
        );
      }),
    );
  }
}
