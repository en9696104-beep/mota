import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../data/models/ai_model.dart';
import '../services/cooperation_pipeline.dart';
import '../services/llama_service.dart';
import '../theme/app_theme.dart';
import '../widgets/model_avatar.dart';

/// 合作系统配置页：总开关 + 各角色模型选择。
///
/// 开启后，管线按角色接力执行（OCR → 主对话、ASR → 主对话、
/// 安全审核闸门、TTS 朗读、向量/重排检索），所有阶段严格串行
/// （load → execute → dispose），同一时刻仅一个模型驻留内存。
class CooperationPage extends StatelessWidget {
  const CooperationPage({super.key});

  @override
  Widget build(BuildContext context) {
    final service = Get.find<CooperationService>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('合作系统', style: TextStyle(fontSize: 17)),
      ),
      body: Obx(() {
        final config = service.config.value;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 总开关
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  '启用合作系统',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  LlamaService.supportsMultimodal
                      ? '多模型接力：OCR / 语音 / 向量 / 安全审核按角色协作'
                      : '当前平台仅支持主对话接力，多模态角色需桌面端',
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                  ),
                ),
                value: config.enabled,
                activeThumbColor: AppColors.accent,
                onChanged: (value) =>
                    service.updateConfig(config.copyWith(enabled: value)),
              ),
            ),
            const SizedBox(height: 16),
            // 角色列表
            ...PipelineRole.values.map(
              (role) => _RoleCard(service: service, role: role),
            ),
            const SizedBox(height: 16),
            // 说明
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 14, color: AppColors.textSecondary),
                      SizedBox(width: 6),
                      Text(
                        '工作原理',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    '· 每个角色选择一个已下载的对应能力模型\n'
                    '· 对话时：安全审核先检查输入 → 图片经 OCR 转文字 → 主对话模型生成回复 → 可一键 TTS 朗读\n'
                    '· 语音输入：录音后由 ASR 模型转文字填入输入框\n'
                    '· 为保护内存，所有模型严格串行加载/卸载，绝不并发',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                      height: 1.7,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }
}

/// 单个角色卡片：图标 + 名称 + 当前选择的模型（点击可改）
class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.service, required this.role});

  final CooperationService service;
  final PipelineRole role;

  IconData get _icon => switch (role) {
    PipelineRole.chat => Icons.chat_bubble_outline,
    PipelineRole.ocr => Icons.document_scanner_outlined,
    PipelineRole.asr => Icons.mic_none,
    PipelineRole.tts => Icons.volume_up_outlined,
    PipelineRole.embedding => Icons.hub_outlined,
    PipelineRole.rerank => Icons.sort,
    PipelineRole.security => Icons.shield_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final selected = service.resolveRole(role);
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: ListTile(
          onTap: () => _openPicker(context),
          leading: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_icon, size: 18, color: AppColors.accent),
          ),
          title: Text(
            role.label,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            selected == null ? role.hint : selected.model.name,
            style: TextStyle(
              color: selected == null
                  ? AppColors.textTertiary
                  : AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected != null)
                ModelAvatar(
                  name: selected.model.name,
                  colorIndex: selected.model.colorIndex,
                  author: selected.model.author,
                  size: 28,
                ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right,
                  size: 16, color: AppColors.textTertiary),
            ],
          ),
        ),
      );
    });
  }

  void _openPicker(BuildContext context) {
    final candidates = service.downloadedModelsFor(role);
    if (candidates.isEmpty) {
      Get.snackbar(
        '没有可用模型',
        '请先下载具备「${role.label}」能力的模型（商店中可筛选）',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _RolePickerSheet(
        role: role,
        candidates: candidates,
        currentId: service.config.value.modelIdFor(role),
        onSelected: (model) {
          service.updateConfig(
            service.config.value.copyWithModel(role, model.id),
          );
          Get.back();
        },
        onCleared: () {
          service.updateConfig(
            service.config.value.copyWithModel(role, null),
          );
          Get.back();
        },
      ),
    );
  }
}

/// 角色模型选择弹窗
class _RolePickerSheet extends StatelessWidget {
  const _RolePickerSheet({
    required this.role,
    required this.candidates,
    required this.currentId,
    required this.onSelected,
    required this.onCleared,
  });

  final PipelineRole role;
  final List<AiModel> candidates;
  final String? currentId;
  final ValueChanged<AiModel> onSelected;
  final VoidCallback onCleared;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '选择${role.label}模型',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: candidates.length,
              itemBuilder: (_, index) {
                final model = candidates[index];
                final selected = model.id == currentId;
                return ListTile(
                  onTap: () => onSelected(model),
                  leading: ModelAvatar(
                    name: model.name,
                    colorIndex: model.colorIndex,
                    author: model.author,
                    size: 36,
                  ),
                  title: Text(
                    model.name,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: Text(
                    '${model.params} · ${model.quant} · ${model.sizeLabel}',
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                  trailing: selected
                      ? const Icon(Icons.check_circle,
                          color: AppColors.accent, size: 20)
                      : null,
                );
              },
            ),
          ),
          if (currentId != null)
            TextButton(
              onPressed: onCleared,
              child: const Text(
                '清除该角色',
                style: TextStyle(color: AppColors.danger, fontSize: 13),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
