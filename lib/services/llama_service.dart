import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

import 'inference/android_llama_engine.dart';
import 'inference/desktop_llamadart_engine.dart';
import 'inference/inference_backend.dart';
import 'inference/llama_turn.dart' show LlamaTurn;
import 'inference/tts_audio.dart' show TtsAudio;

/// 兼容旧导入路径：LlamaTurn 曾定义于本文件
export 'inference/llama_turn.dart' show LlamaTurn;
export 'inference/tts_audio.dart' show TtsAudio;

/// llama.cpp 本地推理引擎门面（应用级单例）。
///
/// 按平台路由到底层实现：
/// - Android / iOS → [AndroidLlamaEngine]（llama_flutter_android）
/// - Windows / macOS / Linux → [DesktopLlamadartEngine]（llamadart）
/// - Web → 无可用引擎（[isEngineAvailable] 为 false）
///
/// UI 层只依赖本门面，不感知平台差异。
class LlamaService {
  LlamaService._();

  static final LlamaService instance = LlamaService._();

  static final AndroidLlamaEngine _mobileEngine = AndroidLlamaEngine();
  static final DesktopLlamadartEngine _desktopEngine = DesktopLlamadartEngine();

  /// 是否走桌面引擎（非 Web 且非移动平台）
  static bool get _useDesktopEngine =>
      !kIsWeb && !(Platform.isAndroid || Platform.isIOS);

  static InferenceBackend get _active =>
      _useDesktopEngine ? _desktopEngine : _mobileEngine;

  /// 当前平台是否有可用推理引擎（仅 Web 不可用）
  static bool get isEngineAvailable => !kIsWeb;

  /// 引擎不可用时的原因说明（供 UI 直接展示）
  static String get engineUnavailableReason =>
      '当前平台（Web）暂不支持本地推理，请使用桌面端或移动端应用';

  /// 当前平台是否支持多模态 / 语音 / 向量能力（仅桌面端）
  static bool get supportsMultimodal => _useDesktopEngine;

  bool get isLoaded => _active.isLoaded;

  String? get loadedPath => _active.loadedPath;

  /// 加载 GGUF 模型（同一路径重复加载直接复用）。
  ///
  /// [projectorPath] 多模态投影器（mmproj）路径，视觉/语音模型必填。
  Future<bool> loadModel(
    String path, {
    int threads = 4,
    int contextSize = 2048,
    String? projectorPath,
  }) =>
      _active.loadModel(
        path,
        threads: threads,
        contextSize: contextSize,
        projectorPath: projectorPath,
      );

  /// 单轮 prompt 流式生成（逐 token 输出）
  Stream<String> generateStream(
    String prompt, {
    double temperature = 0.7,
    int maxTokens = 512,
  }) =>
      _active.generateStream(
        prompt,
        temperature: temperature,
        maxTokens: maxTokens,
      );

  /// 多轮对话流式生成（自动应用聊天模板，逐 token 输出）
  ///
  /// [template] 传 null 时由各后端自行探测。
  Stream<String> generateChatStream(
    List<LlamaTurn> messages, {
    String? template,
    double temperature = 0.7,
    int maxTokens = 512,
  }) =>
      _active.generateChatStream(
        messages,
        template: template,
        temperature: temperature,
        maxTokens: maxTokens,
      );

  /// 带图片输入的多轮对话流式生成（桌面端多模态模型专用）
  Stream<String> generateChatStreamWithMedia(
    List<LlamaTurn> messages, {
    String? template,
    double temperature = 0.7,
    int maxTokens = 512,
  }) =>
      _active.generateChatStreamWithMedia(
        messages,
        template: template,
        temperature: temperature,
        maxTokens: maxTokens,
      );

  /// 语音识别：音频文件 → 文本（自包含执行，前后释放驻留模型）
  Future<String?> transcribeAudio(
    String modelPath,
    String audioPath, {
    String? projectorPath,
  }) =>
      _active.transcribeAudio(
        modelPath,
        audioPath,
        projectorPath: projectorPath,
      );

  /// 语音合成：文本 → PCM（自包含执行，前后释放驻留模型）
  Future<TtsAudio?> synthesizeSpeech(
    String modelPath,
    String text, {
    String? projectorPath,
    String language = 'zh',
  }) =>
      _active.synthesizeSpeech(
        modelPath,
        text,
        projectorPath: projectorPath,
        language: language,
      );

  /// 文本向量化（自包含执行，前后释放驻留模型）
  Future<List<double>?> embedText(String modelPath, String text) =>
      _active.embedText(modelPath, text);

  /// 停止当前生成（已生成内容保留）
  Future<void> stop() => _active.stop();

  /// 释放模型资源
  Future<void> dispose() => _active.dispose();
}
