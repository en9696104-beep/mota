import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/chat_controller.dart';
import '../controllers/main_controller.dart';
import '../controllers/store_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/chat_settings_sheet.dart';
import '../widgets/model_avatar.dart';
import '../widgets/model_name_text.dart';

/// 对话页：本地 llama.cpp 流式推理
class ChatPage extends StatelessWidget {
  const ChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<ChatController>();
    return Scaffold(
      appBar: AppBar(
        leading: Obx(() {
          // 品牌头像：按模型 id 回查商店作者；未知回退字块
          String? author;
          final id = controller.modelId;
          if (id != null && Get.isRegistered<StoreController>()) {
            for (final m in Get.find<StoreController>().models) {
              if (m.id == id) {
                author = m.author;
                break;
              }
            }
          }
          return Center(
            child: ModelAvatar(
              name: controller.modelName.value,
              colorIndex: 0,
              author: author,
              size: 30,
            ),
          );
        }),
        title: Row(
          children: [
            Flexible(
              child: Obx(
                // AppBar 高度固定：字号自适应缩小，单行也要显示完整名称
                () => FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: ModelNameText(
                    controller.modelName.value,
                    maxLines: 1,
                    style: const TextStyle(fontSize: 17),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Obx(() => _StatusDot(controller: controller)),
          ],
        ),
        actions: [
          // TTS 朗读最后一条回复（合作系统）
          IconButton(
            icon: Obx(
              () => Icon(
                controller.isSpeaking.value
                    ? Icons.graphic_eq
                    : Icons.volume_up_outlined,
                size: 20,
              ),
            ),
            tooltip: '朗读回复',
            color: AppColors.textSecondary,
            onPressed: controller.speakLastReply,
          ),
          // 模型高级参数设置
          const IconButton(
            icon: Icon(Icons.tune_rounded, size: 20),
            tooltip: '模型高级参数',
            color: AppColors.textSecondary,
            onPressed: showChatSettingsSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          // 顶部状态条：重载中 / 加载中 / 未下载引导
          Obx(() {
            if (controller.isReloading.value) {
              return const _Banner(
                icon: Icons.autorenew_rounded,
                text: '正在应用新配置并重载模型...',
              );
            }
            if (controller.isLoadingModel.value) {
              return const _Banner(
                icon: Icons.hourglass_empty,
                text: '模型加载中，首次启动可能需要几十秒…',
              );
            }
            // 未下载引导（含从历史记录点入、模型未下载的场景）
            if (!controller.modelReady.value && !controller.hasLocalModel) {
              return _Banner(
                icon: Icons.cloud_download_outlined,
                text: '该模型尚未下载到本地，请先到模型商店下载',
                actionLabel: '去商店',
                onAction: () => Get.find<MainController>().changeTab(1),
              );
            }
            return const SizedBox.shrink();
          }),
          Expanded(
            child: Obx(() {
              if (controller.messages.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      '本地模型已就绪，输入消息开始对话。\n推理全程在本机完成，无需联网。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 13,
                        height: 1.6,
                      ),
                    ),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                reverse: true,
                itemCount: controller.messages.length,
                itemBuilder: (_, index) {
                  final message = controller
                      .messages[controller.messages.length - 1 - index];
                  return _ChatBubble(message: message);
                },
              );
            }),
          ),
          // 待发送图片预览条
          Obx(() {
            if (controller.pendingImages.isEmpty) {
              return const SizedBox.shrink();
            }
            return _PendingImageStrip(controller: controller);
          }),
          _InputBar(controller: controller),
        ],
      ),
    );
  }
}

/// 标题栏模型状态点：绿点 = 就绪，转圈 = 加载中，灰点 = 未就绪
class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.controller});

  final ChatController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.isLoadingModel.value) {
      return const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.accent,
        ),
      );
    }
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: controller.modelReady.value
            ? AppColors.accent
            : AppColors.textTertiary,
      ),
    );
  }
}

/// 顶部提示条
class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppColors.surfaceHigh,
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            GestureDetector(
              onTap: onAction,
              behavior: HitTestBehavior.opaque,
              child: Text(
                actionLabel!,
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 聊天气泡
class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        decoration: BoxDecoration(
          color: isUser ? AppColors.accent : AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 消息附带的图片缩略图
            if (message.imagePaths.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: message.imagePaths.map((path) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(path),
                      width: 120,
                      height: 120,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 120,
                        height: 120,
                        color: AppColors.border,
                        child: const Icon(
                          Icons.broken_image_outlined,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              if (message.text.isNotEmpty) const SizedBox(height: 8),
            ],
            Text(
              message.text.isEmpty ? '…' : message.text,
              style: TextStyle(
                color: isUser ? Colors.black : AppColors.textPrimary,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 待发送图片预览条（输入框上方）
class _PendingImageStrip extends StatelessWidget {
  const _PendingImageStrip({required this.controller});

  final ChatController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.surface,
      child: SizedBox(
        height: 64,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: controller.pendingImages.map((path) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(path),
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 64,
                        height: 64,
                        color: AppColors.border,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: GestureDetector(
                      onTap: () => controller.removePendingImage(path),
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

/// 底部输入栏：生成中变为「停止」按钮
class _InputBar extends StatelessWidget {
  const _InputBar({required this.controller});

  final ChatController controller;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                // 图片输入（OCR 管线 / 视觉模型直传）
                Obx(
                  () => _CircleAction(
                    icon: Icons.image_outlined,
                    tooltip: controller.supportsImageInput.value
                        ? '上传图片'
                        : '当前模型不支持图片输入',
                    enabled: controller.supportsImageInput.value,
                    onTap: controller.pickImages,
                  ),
                ),
                const SizedBox(width: 8),
                // 语音输入（ASR 管线）
                Obx(
                  () => _CircleAction(
                    icon: controller.isTranscribing.value
                        ? Icons.transcribe
                        : (controller.isRecording.value
                              ? Icons.stop_circle_outlined
                              : Icons.mic_none),
                    tooltip: controller.isRecording.value ? '停止录音' : '语音输入',
                    highlight:
                        controller.isRecording.value ||
                        controller.isTranscribing.value,
                    onTap: controller.toggleVoiceInput,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    onChanged: (value) => controller.input.value = value,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                    ),
                    cursorColor: AppColors.accent,
                    decoration: InputDecoration(
                      hintText: controller.isRecording.value
                          ? '录音中，点击左侧按钮停止…'
                          : '输入消息…',
                      hintStyle: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 13,
                      ),
                      filled: true,
                      fillColor: AppColors.surfaceHigh,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      border: border,
                      enabledBorder: border,
                      focusedBorder: border,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Obx(() {
                  if (controller.isGenerating.value) {
                    // 生成中：停止按钮（保留已生成内容）
                    return GestureDetector(
                      onTap: controller.stop,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceHigh,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.accent),
                        ),
                        child: const Icon(
                          Icons.stop,
                          color: AppColors.accent,
                          size: 18,
                        ),
                      ),
                    );
                  }
                  return GestureDetector(
                    onTap: controller.send,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_upward,
                        color: Colors.black,
                        size: 20,
                      ),
                    ),
                  );
                }),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              '当前由本地 llama.cpp 驱动，不联网。',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

/// 输入栏圆形小按钮（图片 / 语音）
class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.highlight = false,
    this.enabled = true,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  /// 高亮态（如录音中：主题色描边）
  final bool highlight;

  /// 禁用态（如当前模型不支持图片输入：置灰且不响应点击）
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? AppColors.textTertiary
        : (highlight ? AppColors.accent : AppColors.textSecondary);
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            shape: BoxShape.circle,
            border: Border.all(
              color: !enabled
                  ? AppColors.border
                  : (highlight ? AppColors.accent : AppColors.border),
            ),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
      ),
    );
  }
}
