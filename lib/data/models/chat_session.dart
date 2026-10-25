/// 一条历史对话记录
class ChatSession {
  const ChatSession({
    required this.id,
    required this.modelName,
    required this.lastMessage,
    required this.updatedAt,
    required this.messageCount,
    required this.colorIndex,
  });

  /// 会话唯一标识
  final String id;

  /// 对话所用模型名称
  final String modelName;

  /// 最后一条消息摘要
  final String lastMessage;

  /// 最后活跃时间
  final DateTime updatedAt;

  /// 消息条数
  final int messageCount;

  /// 头像渐变色索引
  final int colorIndex;
}
