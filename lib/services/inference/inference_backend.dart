import 'llama_turn.dart';
import 'tts_audio.dart';

/// 本地推理引擎统一接口。
///
/// MOTA 按平台路由到不同实现：
/// - Android / iOS：[AndroidLlamaEngine]（llama_flutter_android，ARM64 预编译 AAR）
/// - Windows / macOS / Linux：[DesktopLlamadartEngine]（llamadart，llama.cpp 预编译二进制）
///
/// 两层都只依赖 GGUF；UI 层（ChatController / ApiService / MCP）不感知平台差异。
///
/// 多模态能力（图像 / ASR / TTS / 向量）当前仅桌面端实现；
/// 移动端引擎保持纯文本能力，未实现的方法抛 [UnsupportedError]，
/// 由 UI 层捕获后给出诚实的能力提示。
abstract class InferenceBackend {
  /// 当前是否已加载模型
  bool get isLoaded;

  /// 当前已加载模型的文件路径
  String? get loadedPath;

  /// 加载 GGUF 模型。
  ///
  /// - 同一路径重复加载直接复用
  /// - [threads] 生成线程数，[contextSize] 上下文长度（token）
  /// - [projectorPath] 多模态投影器（mmproj）路径，视觉/语音模型必填
  /// - 返回 false 表示加载失败（由调用方决定提示文案）
  Future<bool> loadModel(
    String path, {
    int threads = 4,
    int contextSize = 2048,
    String? projectorPath,
  });

  /// 单轮 prompt 流式生成（逐段输出）
  Stream<String> generateStream(
    String prompt, {
    double temperature = 0.7,
    int maxTokens = 512,
  });

  /// 多轮对话流式生成（自动应用模型自带聊天模板）
  ///
  /// [template] 为 null 时由实现自行探测；各后端对模板的处理方式不同
  /// （llamadart 用模型内置 Jinja 模板，llama_flutter_android 用内置模板名）。
  Stream<String> generateChatStream(
    List<LlamaTurn> messages, {
    String? template,
    double temperature = 0.7,
    int maxTokens = 512,
  });

  /// 停止当前生成（已生成内容保留）
  Future<void> stop();

  /// 释放模型资源
  Future<void> dispose();

  // ---------- 多模态 / 语音 / 向量（默认仅桌面端支持） ----------

  /// 带图片输入的多轮对话流式生成（[LlamaTurn.imagePaths] 非空时附加图像部件）。
  ///
  /// 未实现多模态的引擎抛 [UnsupportedError]。
  Stream<String> generateChatStreamWithMedia(
    List<LlamaTurn> messages, {
    String? template,
    double temperature = 0.7,
    int maxTokens = 512,
  }) =>
      throw UnsupportedError('当前推理引擎不支持图像输入');

  /// 语音识别：音频文件 → 文本。
  ///
  /// [modelPath] ASR 模型路径，[projectorPath] 音频投影器路径；
  /// 内部自行 load → transcribe → dispose（调用前后会释放当前驻留模型，
  /// 保证同一时刻只有一个模型驻留内存）。
  ///
  /// 未实现的平台抛 [UnsupportedError]。
  Future<String?> transcribeAudio(
    String modelPath,
    String audioPath, {
    String? projectorPath,
  }) =>
      throw UnsupportedError('当前推理引擎不支持语音识别');

  /// 语音合成：文本 → PCM 音频。
  ///
  /// [language] BCP-47 语言码（Qwen3-TTS 取 zh/en/ja 等）。
  /// 内部自行 load → synthesize → dispose。
  ///
  /// 未实现的平台抛 [UnsupportedError]。
  Future<TtsAudio?> synthesizeSpeech(
    String modelPath,
    String text, {
    String? projectorPath,
    String language = 'zh',
  }) =>
      throw UnsupportedError('当前推理引擎不支持语音合成');

  /// 文本向量化（embedding 模型）→ 向量（L2 归一化）。
  ///
  /// [modelPath] embedding 模型路径；内部自行 load → embed → dispose。
  ///
  /// 未实现的平台抛 [UnsupportedError]。
  Future<List<double>?> embedText(String modelPath, String text) =>
      throw UnsupportedError('当前推理引擎不支持向量计算');
}
