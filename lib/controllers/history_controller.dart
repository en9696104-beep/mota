import 'package:get/get.dart';

import '../data/models/chat_session.dart';
import '../data/models/chat_turn.dart';
import '../routes/app_routes.dart';
import '../services/chat_history_db.dart';
import '../services/model_repository.dart';
import '../services/storage_service.dart';

/// 「历史对话」页状态：sqflite 持久化的真实聊天记录
class HistoryController extends GetxController {
  final sessions = <ChatSession>[].obs;

  /// 读取中（数据库查询是异步的）
  final loading = false.obs;

  @override
  void onInit() {
    super.onInit();
    loadFromDatabase();
  }

  /// 从数据库读取全部轮次，按模型聚合为会话，按时间倒序渲染
  Future<void> loadFromDatabase() async {
    loading.value = true;
    final turns = await ChatHistoryDatabase.instance.allTurnsDesc();
    // 按模型分组（turns 已按时间倒序，每组首条即最新一轮）
    final grouped = <String, List<ChatTurn>>{};
    for (final turn in turns) {
      grouped.putIfAbsent(turn.modelId, () => <ChatTurn>[]).add(turn);
    }
    final list = grouped.entries.map((entry) {
      final modelTurns = entry.value;
      final latest = modelTurns.first;
      return ChatSession(
        id: entry.key,
        modelName: latest.modelName,
        lastMessage: latest.assistantContent,
        updatedAt: latest.createdAt,
        messageCount: modelTurns.length,
        // 头像色：优先取商店目录中的 colorIndex，未下载的模型回退 0
        colorIndex: ModelRepository.to.byId(entry.key)?.colorIndex ?? 0,
      );
    }).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    sessions.assignAll(list);
    loading.value = false;
  }

  /// 删除会话（左滑删除）：同步删除该模型的全部轮次
  Future<void> deleteSession(String id) async {
    sessions.removeWhere((s) => s.id == id);
    await ChatHistoryDatabase.instance.deleteTurnsForModel(id);
  }

  /// 打开会话，跳转对话页（携带本地模型路径，未下载则只带模型名）
  void openSession(ChatSession session) {
    final path = StorageService.to.pathFor(session.id);
    Get.toNamed(
      AppRoutes.chat,
      arguments: <String, dynamic>{
        'sessionId': session.id,
        'modelId': session.id,
        'modelName': session.modelName,
        if (path != null) 'modelPath': path,
      },
    );
  }
}
