import 'dart:async';
import 'dart:convert';

import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/ai_model.dart';
import '../services/llama_service.dart';
import '../services/model_repository.dart';
import '../services/storage_service.dart';

/// 群聊成员：一个已下载到本地的对话模型
class GroupMember {
  GroupMember({
    required this.modelId,
    required this.modelName,
    required this.colorIndex,
    required this.path,
    this.author = '',
    this.projectorPath,
    this.chatTemplate,
  });

  final String modelId;
  final String modelName;

  /// 头像渐变色索引（与商店 colorIndex 一致）
  final int colorIndex;

  /// 作者/厂商（匹配品牌图标；旧记录为空串则回退字块头像）
  final String author;

  /// 本地 GGUF 路径
  final String path;

  /// 投影器路径（多模态成员用）
  final String? projectorPath;

  /// 聊天模板
  final String? chatTemplate;

  Map<String, dynamic> toJson() => {
    'modelId': modelId,
    'modelName': modelName,
    'colorIndex': colorIndex,
    'path': path,
    'author': author,
    'projectorPath': projectorPath,
    'chatTemplate': chatTemplate,
  };

  static GroupMember? fromJson(Map<String, dynamic> json) {
    final path = json['path'] as String?;
    final modelId = json['modelId'] as String?;
    if (path == null || modelId == null) return null;
    return GroupMember(
      modelId: modelId,
      modelName: json['modelName'] as String? ?? modelId,
      colorIndex: (json['colorIndex'] as num?)?.toInt() ?? 0,
      path: path,
      author: json['author'] as String? ?? '',
      projectorPath: json['projectorPath'] as String?,
      chatTemplate: json['chatTemplate'] as String?,
    );
  }
}

/// 群聊消息（成员发言带成员标识；用户消息 isUser = true）
class GroupChatMessage {
  GroupChatMessage({
    required this.text,
    required this.time,
    this.member,
    this.isUser = false,
    this.isSystem = false,
  });

  /// 发言成员（null 表示用户消息或系统消息）
  final GroupMember? member;

  String text;
  final DateTime time;

  /// 是否为用户本人消息
  final bool isUser;

  /// 是否为系统提示消息（如某成员加载失败）
  final bool isSystem;

  /// 发言者名称
  String get senderName =>
      isSystem ? '系统' : (isUser ? '我' : (member?.modelName ?? 'AI'));

  /// 头像颜色索引（系统消息用中性色）
  int get colorIndex => member?.colorIndex ?? 0;
}

/// 群聊控制器：多个本地 AI 模型轮流对话。
///
/// 核心约束（用户明确要求）：
/// - **禁止并发 AI**：同一时刻只允许一个模型驻留内存。
///   实现为严格串行——每个成员发言前加载其模型（loadModel 内部会先
///   释放上一个模型），发言流结束后整体释放，绝不允许两个引擎并存。
/// - **AI 互相可见**：所有成员共享同一份聊天历史，每条消息带发言者
///   名称，系统提示中说明群聊场景与成员名单。
class GroupChatController extends GetxController {
  static const String _membersPrefsKey = 'group_chat_members_v1';

  final members = <GroupMember>[].obs;
  final messages = <GroupChatMessage>[].obs;

  /// 是否正在生成（含成员轮流发言全过程）
  final isGenerating = false.obs;

  /// 当前正在发言的成员名（UI 显示「XX 正在输入…」）
  final currentSpeaker = ''.obs;

  bool _stopRequested = false;
  StreamSubscription<String>? _subscription;

  @override
  void onInit() {
    super.onInit();
    _restoreMembers();
  }

  /// 恢复上次群聊成员配置
  Future<void> _restoreMembers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_membersPrefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = (jsonDecode(raw) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(GroupMember.fromJson)
          .whereType<GroupMember>()
          // 过滤已删除的本地模型
          .where((m) => StorageService.to.pathFor(m.modelId) != null)
          .toList();
      members.assignAll(list);
    } catch (_) {
      // 配置损坏时忽略，从空成员列表开始
    }
  }

  Future<void> _persistMembers() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _membersPrefsKey,
      jsonEncode(members.map((m) => m.toJson()).toList()),
    );
  }

  /// 已下载且具备对话能力的模型（成员选择器数据源）
  List<AiModel> get availableChatModels {
    if (!Get.isRegistered<ModelRepository>()) return const <AiModel>[];
    return ModelRepository.to.models
        .where((m) => StorageService.to.pathFor(m.id) != null)
        .where((m) => m.hasCapability(ModelCapability.chat))
        .toList();
  }

  /// 切换成员（已下载模型）；返回是否操作成功
  Future<bool> toggleMember(AiModel model) async {
    if (isMember(model.id)) {
      members.removeWhere((m) => m.modelId == model.id);
      await _persistMembers();
      return true;
    }
    final path = StorageService.to.pathFor(model.id);
    if (path == null) return false;
    members.add(
      GroupMember(
        modelId: model.id,
        modelName: model.name,
        colorIndex: model.colorIndex,
        path: path,
        author: model.author,
        projectorPath: StorageService.to.projectorPathFor(model.id),
        chatTemplate: model.chatTemplate,
      ),
    );
    await _persistMembers();
    return true;
  }

  bool isMember(String modelId) => members.any((m) => m.modelId == modelId);

  /// 清空聊天记录（保留成员）
  void clearMessages() => messages.clear();

  /// 发送消息：用户消息广播给所有成员，成员**串行**轮流回复。
  void send(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (isGenerating.value) return;
    if (members.isEmpty) {
      Get.snackbar(
        '还没有群成员',
        '请先点击右上角添加至少一个 AI 模型',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    messages.add(
      GroupChatMessage(text: trimmed, time: DateTime.now(), isUser: true),
    );
    _runRounds();
  }

  /// 串行执行每个成员的回复（禁并发的核心）
  Future<void> _runRounds() async {
    isGenerating.value = true;
    _stopRequested = false;

    for (final member in members) {
      if (_stopRequested) break;
      // 内存保护：加载新成员模型前，LlamaService.loadModel 内部会先
      // 释放上一个成员模型——同一时刻仅一个模型驻留内存。
      final ok = await LlamaService.instance.loadModel(
        member.path,
        projectorPath: member.projectorPath,
      );
      if (!ok) {
        messages.add(
          GroupChatMessage(
            text: '${member.modelName} 加载失败，已跳过',
            time: DateTime.now(),
            isSystem: true,
          ),
        );
        continue;
      }

      final reply = GroupChatMessage(
        text: '',
        time: DateTime.now(),
        member: member,
      );
      messages.add(reply);
      currentSpeaker.value = member.modelName;

      final buffer = StringBuffer();
      final completer = Completer<void>();
      _subscription = LlamaService.instance
          .generateChatStream(
            _buildHistoryFor(member),
            template: member.chatTemplate,
            temperature: 0.7,
          )
          .listen(
            (token) {
              buffer.write(token);
              reply.text = buffer.toString();
              messages.refresh();
            },
            onError: (Object error) {
              reply.text = '${buffer.toString()}（生成失败：$error）';
              messages.refresh();
              if (!completer.isCompleted) completer.complete();
            },
            onDone: () {
              if (!completer.isCompleted) completer.complete();
            },
          );
      await completer.future;

      if (_stopRequested) break;
    }

    // 全部结束：彻底释放内存（不留任何模型驻留）
    await LlamaService.instance.dispose();
    _subscription?.cancel();
    _subscription = null;
    currentSpeaker.value = '';
    isGenerating.value = false;
  }

  /// 为某成员构造上下文：系统提示（群聊身份 + 成员名单）+ 共享历史。
  ///
  /// 共享历史中每条消息带发言者名称，保证 AI 之间互相可见彼此发言。
  List<LlamaTurn> _buildHistoryFor(GroupMember member) {
    final otherNames = members
        .where((m) => m.modelId != member.modelId)
        .map((m) => m.modelName)
        .toList();
    final systemPrompt = StringBuffer(
      '你正在一个多 AI 群聊中与用户和其他 AI 对话。'
      '你的名字是「${member.modelName}」。',
    );
    if (otherNames.isNotEmpty) {
      systemPrompt.write('群里的其他 AI 成员有：${otherNames.join('、')}。');
    }
    systemPrompt.write(
      '你能看到本群全部聊天记录（含其他 AI 的发言）。'
      '请基于聊天记录给出你的回复：直接陈述观点或回答用户，'
      '可以简短回应其他 AI 的说法，不要重复别人已经说过的内容，'
      '不要输出自己的名字前缀。',
    );

    return <LlamaTurn>[
      LlamaTurn(role: 'system', content: systemPrompt.toString()),
      ...messages
          .where((m) => m.text.isNotEmpty)
          .map(
            (m) => LlamaTurn(
              role: m.isUser ? 'user' : 'assistant',
              content: m.isUser ? m.text : '【${m.senderName}】${m.text}',
            ),
          ),
    ];
  }

  /// 停止生成：中断当前成员发言，已生成内容保留
  void stop() {
    _stopRequested = true;
    _subscription?.cancel();
    _subscription = null;
    LlamaService.instance.stop();
  }

  @override
  void onClose() {
    _subscription?.cancel();
    LlamaService.instance.dispose();
    super.onClose();
  }
}
