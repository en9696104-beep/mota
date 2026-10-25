import 'package:llama_flutter_android/llama_flutter_android.dart' as lfa;

import '../inference/inference_backend.dart';
import '../inference/llama_turn.dart';
import '../inference/tts_audio.dart' show TtsAudio;

/// 移动端推理引擎：llama_flutter_android（Android / iOS）。
///
/// 底层为 Pigeon 类型安全桥接 + 插件自带 ARM64 预编译 AAR，无需手动编译 llama.cpp。
/// 逻辑自 v2.7 前的 LlamaService 原样迁移，保持行为不变。
class AndroidLlamaEngine implements InferenceBackend {
  lfa.LlamaController? _controller;
  String? _loadedPath;
  bool _loading = false;

  @override
  bool get isLoaded => _loadedPath != null;

  @override
  String? get loadedPath => _loadedPath;

  @override
  Future<bool> loadModel(
    String path, {
    int threads = 4,
    int contextSize = 2048,
    String? projectorPath,
  }) async {
    // 多模态模型（需投影器）在移动端不可用：llama_flutter_android 的
    // ChatMessage 仅支持纯文本，加载了也无法输入图像/音频，直接拒绝，
    // 由 UI 层给出诚实提示，避免静默失败。
    if (projectorPath != null && projectorPath.isNotEmpty) return false;
    if (_loading) return false;
    if (_loadedPath == path && _controller != null) return true;
    _loading = true;
    try {
      // 先释放上一个模型，避免内存泄漏
      if (_controller != null) {
        await _controller!.dispose();
        _controller = null;
        _loadedPath = null;
      }

      final controller = lfa.LlamaController();
      var gpuLayers = 0;
      try {
        final gpu = await controller.detectGpu();
        gpuLayers = gpu.recommendedGpuLayers;
      } catch (_) {
        gpuLayers = 0; // GPU 检测失败：回退纯 CPU
      }

      await controller.loadModel(
        modelPath: path,
        threads: threads,
        contextSize: contextSize,
        gpuLayers: gpuLayers,
      );
      _controller = controller;
      _loadedPath = path;
      return true;
    } catch (_) {
      _controller = null;
      _loadedPath = null;
      return false;
    } finally {
      _loading = false;
    }
  }

  @override
  Stream<String> generateStream(
    String prompt, {
    double temperature = 0.7,
    int maxTokens = 512,
  }) {
    final controller = _controller;
    if (controller == null) return const Stream<String>.empty();
    return controller.generate(
      prompt: prompt,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  @override
  Stream<String> generateChatStream(
    List<LlamaTurn> messages, {
    String? template,
    double temperature = 0.7,
    int maxTokens = 512,
  }) {
    final controller = _controller;
    if (controller == null) return const Stream<String>.empty();
    return controller.generateChat(
      messages: messages
          .map((m) => lfa.ChatMessage(role: m.role, content: m.content))
          .toList(),
      template: template,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  @override
  Future<void> stop() async {
    try {
      await _controller?.stop();
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    try {
      await _controller?.dispose();
    } catch (_) {}
    _controller = null;
    _loadedPath = null;
  }

  // ---------- 多模态 / 语音 / 向量：移动端诚实降级 ----------
  //
  // llama_flutter_android 0.2.6 的 ChatMessage 仅支持纯文本，
  // 无图像/音频输入通道；ASR / TTS / embedding 引擎亦未接入。
  // 这些能力当前仅桌面端（llamadart）提供，移动端调用直接抛出
  // 带说明的 UnsupportedError，由 UI 层捕获后提示用户。

  @override
  Stream<String> generateChatStreamWithMedia(
    List<LlamaTurn> messages, {
    String? template,
    double temperature = 0.7,
    int maxTokens = 512,
  }) =>
      throw UnsupportedError('移动端暂不支持图像输入，请使用桌面端');

  @override
  Future<String?> transcribeAudio(
    String modelPath,
    String audioPath, {
    String? projectorPath,
  }) =>
      throw UnsupportedError('移动端暂不支持语音识别，请使用桌面端');

  @override
  Future<TtsAudio?> synthesizeSpeech(
    String modelPath,
    String text, {
    String? projectorPath,
    String language = 'zh',
  }) =>
      throw UnsupportedError('移动端暂不支持语音合成，请使用桌面端');

  @override
  Future<List<double>?> embedText(String modelPath, String text) =>
      throw UnsupportedError('移动端暂不支持向量计算，请使用桌面端');
}
