/// 一条聊天轮次记录（用户问 + 助手答），持久化于 sqflite
class ChatTurn {
  const ChatTurn({
    this.id,
    required this.modelId,
    required this.modelName,
    required this.createdAt,
    required this.userContent,
    required this.assistantContent,
  });

  /// 数据库自增主键（未入库时为 null）
  final int? id;

  /// 所属模型 id（store_data.json 中的模型标识）
  final String modelId;

  /// 所属模型名称（冗余存储，历史列表展示用，避免反查目录）
  final String modelName;

  /// 轮次完成时间
  final DateTime createdAt;

  /// 用户消息内容
  final String userContent;

  /// 助手回复内容（流式接收完毕后的完整文本）
  final String assistantContent;

  Map<String, dynamic> toMap() => <String, dynamic>{
    'id': id,
    'model_id': modelId,
    'model_name': modelName,
    'created_at': createdAt.millisecondsSinceEpoch,
    'user_content': userContent,
    'assistant_content': assistantContent,
  };

  factory ChatTurn.fromMap(Map<String, dynamic> map) => ChatTurn(
    id: map['id'] as int?,
    modelId: map['model_id'] as String,
    modelName: map['model_name'] as String? ?? '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    userContent: map['user_content'] as String,
    assistantContent: map['assistant_content'] as String? ?? '',
  );
}
