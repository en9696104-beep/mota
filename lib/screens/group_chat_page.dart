import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/group_chat_controller.dart';
import '../data/models/ai_model.dart';
import '../theme/app_theme.dart';
import '../widgets/model_avatar.dart';

/// 群聊页：多个本地 AI 轮流对话（严格串行，禁止并发驻留内存）。
class GroupChatPage extends StatelessWidget {
  const GroupChatPage({super.key});

  /// 打开成员选择弹窗
  void _showMemberPicker() {
    showModalBottomSheet(
      context: Get.context!,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const MemberPickerSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(GroupChatController());
    return Scaffold(
      appBar: AppBar(
        title: Obx(() {
          final count = controller.members.length;
          return Text(
            count == 0 ? '群聊' : '群聊（$count 位 AI）',
            style: const TextStyle(fontSize: 17),
          );
        }),
        actions: [
          // 清空聊天记录
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            tooltip: '清空聊天记录',
            color: AppColors.textSecondary,
            onPressed: controller.clearMessages,
          ),
          // 成员管理
          IconButton(
            icon: const Icon(Icons.group_add_outlined, size: 20),
            tooltip: '管理群成员',
            color: AppColors.textSecondary,
            onPressed: _showMemberPicker,
          ),
        ],
      ),
      body: Column(
        children: [
          // 成员条：横滑展示当前成员头像
          Obx(() {
            if (controller.members.isEmpty) {
              return _EmptyMemberBanner(onTap: _showMemberPicker);
            }
            return _MemberStrip(controller: controller);
          }),
          Expanded(
            child: Obx(() {
              if (controller.messages.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      '群聊中多位 AI 将依次发言。\n为避免内存溢出，AI 逐个串行回复（同一时刻仅一个模型驻留内存）。',
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
                  return _GroupBubble(message: message);
                },
              );
            }),
          ),
          _GroupInputBar(controller: controller),
        ],
      ),
    );
  }
}

/// 成员横条：头像 + 名称，正在发言者高亮
class _MemberStrip extends StatelessWidget {
  const _MemberStrip({required this.controller});

  final GroupChatController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Obx(
          () => Row(
            children: controller.members.map((m) {
              final speaking = controller.currentSpeaker.value == m.modelName;
              return Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Column(
                  children: [
                    Stack(
                      children: [
                        ModelAvatar(
                          name: m.modelName,
                          colorIndex: m.colorIndex,
                          author: m.author,
                          size: 34,
                        ),
                        if (speaking)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                color: AppColors.accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      m.modelName,
                      style: TextStyle(
                        color: speaking
                            ? AppColors.accent
                            : AppColors.textTertiary,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

/// 无成员时的引导条
class _EmptyMemberBanner extends StatelessWidget {
  const _EmptyMemberBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        color: AppColors.surfaceHigh,
        child: const Row(
          children: [
            Icon(Icons.group_add_outlined,
                size: 16, color: AppColors.textSecondary),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '还没有群成员，点击添加已下载的 AI 模型（至少 1 个）',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// 群聊气泡：带发言者名称与头像
class _GroupBubble extends StatelessWidget {
  const _GroupBubble({required this.message});

  final GroupChatMessage message;

  @override
  Widget build(BuildContext context) {
    if (message.isSystem) {
      return Center(
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            message.text,
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 11,
            ),
          ),
        ),
      );
    }

    final isUser = message.isUser;
    final bubbleColor =
        isUser ? AppColors.accent : AppColors.surfaceHigh;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.74,
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // 发言者标识：头像 + 名称（AI 之间互相可见的关键）
            if (!isUser)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Row(
                  children: [
                    ModelAvatar(
                      name: message.senderName,
                      colorIndex: message.colorIndex,
                      author: message.member?.author,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      message.senderName,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                message.text.isEmpty ? '…' : message.text,
                style: TextStyle(
                  color: isUser ? Colors.black : AppColors.textPrimary,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 群聊输入栏：发送 / 停止（生成中）
class _GroupInputBar extends StatelessWidget {
  const _GroupInputBar({required this.controller});

  final GroupChatController controller;

  @override
  Widget build(BuildContext context) {
    final inputController = TextEditingController();
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
                Expanded(
                  child: TextField(
                    controller: inputController,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                    ),
                    cursorColor: AppColors.accent,
                    decoration: InputDecoration(
                      hintText: '说点什么，群里的 AI 都会看到…',
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
                    onTap: () {
                      final text = inputController.text;
                      if (text.trim().isEmpty) return;
                      inputController.clear();
                      controller.send(text);
                    },
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
            // 串行执行提示 + 当前发言者
            Obx(() {
              if (!controller.isGenerating.value) {
                return const SizedBox.shrink();
              }
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${controller.currentSpeaker.value} 正在输入…（串行生成，禁止并发）',
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 10,
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// 成员选择底部弹窗：从已下载的对话模型中多选
class MemberPickerSheet extends StatelessWidget {
  const MemberPickerSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<GroupChatController>();
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  '选择群成员',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  '（已下载的对话模型）',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: Obx(() {
              final available = controller.availableChatModels;
              if (available.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    '还没有已下载的对话模型\n请先到模型商店下载',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 13,
                    ),
                  ),
                );
              }
              return ListView.builder(
                shrinkWrap: true,
                itemCount: available.length,
                itemBuilder: (_, index) {
                  final model = available[index];
                  return _MemberPickerTile(
                    model: model,
                    selected: controller.isMember(model.id),
                    onTap: () => controller.toggleMember(model),
                  );
                },
              );
            }),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _MemberPickerTile extends StatelessWidget {
  const _MemberPickerTile({
    required this.model,
    required this.selected,
    required this.onTap,
  });

  final AiModel model;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
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
      trailing: Icon(
        selected ? Icons.check_circle : Icons.add_circle_outline,
        color: selected ? AppColors.accent : AppColors.textTertiary,
        size: 20,
      ),
    );
  }
}
