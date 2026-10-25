import 'package:llamadart/llamadart.dart' as ld;

import '../inference/inference_backend.dart';
import '../inference/llama_turn.dart';
import '../inference/tts_audio.dart';

/// 桌面端推理引擎：llamadart（Windows / macOS / Linux）。
///
/// 底层 llama.cpp 预编译二进制由包构建钩子经 native assets 自动分发
/// （Linux/Windows 走 Vulkan，macOS 走 Metal，无 GPU 时自动回退 CPU），
/// 无需本地 C++ 工具链。聊天模板由 llamadart 按模型元数据自动应用。
///
/// 多模态 / 语音 / 向量方法（图像输入、ASR、TTS、embedding）均为
/// **自包含执行**：内部先释放当前驻留模型，再加载专用模型 → 执行 → 释放，
/// 保证任意时刻只有一个模型驻留内存（群聊「禁止并发 AI」的根基）。
class DesktopLlamadartEngine implements InferenceBackend {
  ld.LlamaEngine? _engine;
  String? _loadedPath;

  @override
  bool get isLoaded => _engine != null && _loadedPath != null;

  @override
  String? get loadedPath => _loadedPath;

  @override
  Future<bool> loadModel(
    String path, {
    int threads = 4,
    int contextSize = 2048,
    String? projectorPath,
  }) async {
    // 先释放上一个模型，避免内存泄漏
    await _releaseEngine();

    final modelParams = ld.ModelParams(
      contextSize: contextSize,
      numberOfThreads: threads,
    );

    // 首选自动后端（Vulkan / Metal / CPU 回退）；
    // 失败时（如无 Vulkan 驱动或显存不足）降级纯 CPU 重试一次。
    for (final gpuLayers in <int?>[null, 0]) {
      try {
        final params = gpuLayers == null
            ? modelParams
            : ld.ModelParams(
                contextSize: contextSize,
                numberOfThreads: threads,
                gpuLayers: gpuLayers,
              );
        final engine = await ld.LlamaEngine.load(
          ld.LlamaModel(
            ld.ModelSource.path(path),
            projector: projectorPath == null
                ? null
                : ld.ModelSource.path(projectorPath),
          ),
          params: params,
        );
        _engine = engine;
        _loadedPath = path;
        return true;
      } catch (e) {
        // 最后一次尝试（CPU 档）仍失败则放弃
        if (gpuLayers == 0) {
          await _releaseEngine();
          return false;
        }
      }
    }
    return false;
  }

  @override
  Stream<String> generateStream(
    String prompt, {
    double temperature = 0.7,
    int maxTokens = 512,
  }) {
    final engine = _engine;
    if (engine == null) return const Stream<String>.empty();
    return engine
        .generate(
          prompt,
          params: ld.GenerationParams(
            maxTokens: maxTokens,
            temp: temperature,
          ),
        )
        .map((token) => token);
  }

  @override
  Stream<String> generateChatStream(
    List<LlamaTurn> messages, {
    String? template,
    double temperature = 0.7,
    int maxTokens = 512,
  }) async* {
    final engine = _engine;
    if (engine == null) return;

    final ldMessages = messages.map((m) {
      final role = switch (m.role) {
        'system' => ld.LlamaChatRole.system,
        'assistant' => ld.LlamaChatRole.assistant,
        _ => ld.LlamaChatRole.user,
      };
      return ld.LlamaChatMessage.fromText(role: role, text: m.content);
    }).toList();

    await for (final chunk in engine.create(
      ldMessages,
      params: ld.GenerationParams(
        maxTokens: maxTokens,
        temp: temperature,
      ),
    )) {
      if (chunk.text.isNotEmpty) yield chunk.text;
    }
  }

  @override
  Stream<String> generateChatStreamWithMedia(
    List<LlamaTurn> messages, {
    String? template,
    double temperature = 0.7,
    int maxTokens = 512,
  }) async* {
    final engine = _engine;
    if (engine == null) return;

    final ldMessages = messages.map((m) {
      final role = switch (m.role) {
        'system' => ld.LlamaChatRole.system,
        'assistant' => ld.LlamaChatRole.assistant,
        _ => ld.LlamaChatRole.user,
      };
      // 带图片的消息：媒体部件置于文本之前（llamadart 多模态约定）
      if (m.imagePaths.isNotEmpty) {
        return ld.LlamaChatMessage.withContent(
          role: role,
          content: <ld.LlamaContentPart>[
            ...m.imagePaths.map((p) => ld.LlamaImageContent(path: p)),
            ld.LlamaTextContent(m.content),
          ],
        );
      }
      return ld.LlamaChatMessage.fromText(role: role, text: m.content);
    }).toList();

    await for (final chunk in engine.create(
      ldMessages,
      params: ld.GenerationParams(
        maxTokens: maxTokens,
        temp: temperature,
      ),
    )) {
      if (chunk.text.isNotEmpty) yield chunk.text;
    }
  }

  @override
  Future<String?> transcribeAudio(
    String modelPath,
    String audioPath, {
    String? projectorPath,
  }) async {
    // 内存保护：先释放当前驻留的聊天模型（单模型驻留约束）
    await _releaseEngine();

    final recognizer = await ld.SpeechToTextEngine.load(
      ld.SpeechToTextModel(
        ld.ModelSource.path(modelPath),
        projector: projectorPath == null
            ? null
            : ld.ModelSource.path(projectorPath),
        adapter: const ld.Qwen3AsrAdapter(),
      ),
    );
    try {
      final result = await recognizer.transcribeOnce(
        ld.SpeechToTextRequest(
          audio: ld.SpeechAudioFileInput(audioPath),
          maxOutputTokens: 2048,
        ),
      );
      return result.text.trim();
    } finally {
      // 无论成败都释放 ASR 引擎（含其内部 LlamaEngine）
      await recognizer.dispose();
    }
  }

  @override
  Future<TtsAudio?> synthesizeSpeech(
    String modelPath,
    String text, {
    String? projectorPath,
    String language = 'zh',
  }) async {
    // 内存保护：先释放当前驻留的聊天模型（单模型驻留约束）
    await _releaseEngine();

    final synthesizer = await ld.TextToSpeechEngine.load(
      ld.TextToSpeechModel(
        ld.ModelSource.path(modelPath),
        projector: projectorPath == null
            ? null
            : ld.ModelSource.path(projectorPath),
        adapter: const ld.Qwen3TtsAdapter(),
      ),
    );
    try {
      final result = await synthesizer.synthesizeOnce(
        ld.TextToSpeechRequest(text: text, language: language),
      );
      return TtsAudio(
        samples: result.samples,
        sampleRateHz: result.sampleRateHz,
        channelCount: result.channelCount,
      );
    } finally {
      await synthesizer.dispose();
    }
  }

  @override
  Future<List<double>?> embedText(String modelPath, String text) async {
    // 内存保护：先释放当前驻留的聊天模型（单模型驻留约束）
    await _releaseEngine();
    final ok = await loadModel(modelPath);
    if (!ok) return null;
    try {
      return await _engine!.embed(text);
    } finally {
      await _releaseEngine();
    }
  }

  @override
  Future<void> stop() async {
    try {
      // cancelGeneration 返回 void（同步触发取消），不可 await
      _engine?.cancelGeneration();
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    await _releaseEngine();
  }

  Future<void> _releaseEngine() async {
    final engine = _engine;
    _engine = null;
    _loadedPath = null;
    if (engine == null) return;
    try {
      await engine.dispose();
    } catch (_) {}
  }
}
