/// 喂给推理引擎的一轮对话
class LlamaTurn {
  const LlamaTurn({
    required this.role,
    required this.content,
    this.imagePaths = const <String>[],
  });

  /// 'system' / 'user' / 'assistant'
  final String role;

  /// 文本内容
  final String content;

  /// 附带的本地图片路径（多模态模型专用，媒体置于文本之前）
  final List<String> imagePaths;
}
