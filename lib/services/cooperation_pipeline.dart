import 'dart:convert';

import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/ai_model.dart';
import 'llama_service.dart';
import 'model_repository.dart';
import 'ocr_service.dart';
import 'storage_service.dart';

/// 合作管线角色。
///
/// 开启合作系统后，用户为每个角色选择一个已下载的对应能力模型；
/// 管线执行时按角色接力（如：图片 → OCR → 主对话模型 → 回复）。
enum PipelineRole {
  chat('主对话', '管线的主推理模型，产出最终回复'),
  ocr('OCR 识别', '图片 → 文字（文档 / 截图识别）'),
  asr('语音识别', '语音 → 文字（语音输入）'),
  tts('语音合成', '文字 → 语音（朗读回复）'),
  embedding('向量', '文本向量化（RAG / 语义检索）'),
  rerank('重排', '检索结果相关性重排'),
  security('安全审核', '输入/输出内容安全闸门');

  const PipelineRole(this.label, this.hint);

  /// 角色展示名
  final String label;

  /// 角色能力说明
  final String hint;

  /// 该角色要求的模型能力
  ModelCapability get requiredCapability => switch (this) {
    PipelineRole.chat => ModelCapability.chat,
    PipelineRole.ocr => ModelCapability.ocr,
    PipelineRole.asr => ModelCapability.asr,
    PipelineRole.tts => ModelCapability.tts,
    PipelineRole.embedding => ModelCapability.embedding,
    PipelineRole.rerank => ModelCapability.rerank,
    PipelineRole.security => ModelCapability.security,
  };
}

/// 合作管线配置（shared_preferences 持久化）。
///
/// 每个角色保存已下载模型的 id；null 表示该角色未配置。
class CooperationConfig {
  CooperationConfig({
    this.enabled = false,
    this.chatModelId,
    this.ocrModelId,
    this.ocrPrompt,
    this.asrModelId,
    this.ttsModelId,
    this.embeddingModelId,
    this.rerankModelId,
    this.securityModelId,
  });
  /// 合作系统总开关
  bool enabled;

  /// 主对话模型 id
  String? chatModelId;

  /// OCR 模型 id
  String? ocrModelId;

  /// OCR 提示词（null 时用 [defaultOcrPrompt]）
  String? ocrPrompt;

  /// ASR 模型 id
  String? asrModelId;

  /// TTS 模型 id
  String? ttsModelId;

  /// 向量模型 id
  String? embeddingModelId;

  /// 重排模型 id
  String? rerankModelId;

  /// 安全审核模型 id
  String? securityModelId;

  static const String _prefsKey = 'cooperation_pipeline_v1';

  /// 默认 OCR 提示词
  static const String defaultOcrPrompt =
      '请识别并转录这张图片中的全部内容：文字逐行转录，保持原有格式；'
      '图表、流程图请用文字描述其结构与数据关系；如有表格请用 Markdown 表格输出。'
      '不要添加任何评价或解释。';

  /// 生效的 OCR 提示词
  String get effectiveOcrPrompt =>
      (ocrPrompt == null || ocrPrompt!.trim().isEmpty)
          ? defaultOcrPrompt
          : ocrPrompt!.trim();

  /// 按角色读取配置的模型 id
  String? modelIdFor(PipelineRole role) => switch (role) {
    PipelineRole.chat => chatModelId,
    PipelineRole.ocr => ocrModelId,
    PipelineRole.asr => asrModelId,
    PipelineRole.tts => ttsModelId,
    PipelineRole.embedding => embeddingModelId,
    PipelineRole.rerank => rerankModelId,
    PipelineRole.security => securityModelId,
  };

  /// 按角色写入配置的模型 id
  void setModelIdFor(PipelineRole role, String? id) {
    switch (role) {
      case PipelineRole.chat:
        chatModelId = id;
      case PipelineRole.ocr:
        ocrModelId = id;
      case PipelineRole.asr:
        asrModelId = id;
      case PipelineRole.tts:
        ttsModelId = id;
      case PipelineRole.embedding:
        embeddingModelId = id;
      case PipelineRole.rerank:
        rerankModelId = id;
      case PipelineRole.security:
        securityModelId = id;
    }
  }

  /// 复制并仅修改某个角色的模型 id（UI 层便捷方法）
  CooperationConfig copyWithModel(PipelineRole role, String? id) {
    final next = copyWith();
    next.setModelIdFor(role, id);
    return next;
  }

  /// 已配置的角色数（不含 chat）
  int get configuredAuxRoleCount =>
      PipelineRole.values.where((r) => r != PipelineRole.chat && modelIdFor(r) != null).length;

  CooperationConfig copyWith({
    bool? enabled,
    String? chatModelId,
    String? ocrModelId,
    String? ocrPrompt,
    String? asrModelId,
    String? ttsModelId,
    String? embeddingModelId,
    String? rerankModelId,
    String? securityModelId,
  }) =>
      CooperationConfig(
        enabled: enabled ?? this.enabled,
        chatModelId: chatModelId ?? this.chatModelId,
        ocrModelId: ocrModelId ?? this.ocrModelId,
        ocrPrompt: ocrPrompt ?? this.ocrPrompt,
        asrModelId: asrModelId ?? this.asrModelId,
        ttsModelId: ttsModelId ?? this.ttsModelId,
        embeddingModelId: embeddingModelId ?? this.embeddingModelId,
        rerankModelId: rerankModelId ?? this.rerankModelId,
        securityModelId: securityModelId ?? this.securityModelId,
      );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'chatModelId': chatModelId,
    'ocrModelId': ocrModelId,
    'ocrPrompt': ocrPrompt,
    'asrModelId': asrModelId,
    'ttsModelId': ttsModelId,
    'embeddingModelId': embeddingModelId,
    'rerankModelId': rerankModelId,
    'securityModelId': securityModelId,
  };

  static CooperationConfig fromJson(Map<String, dynamic> json) =>
      CooperationConfig(
        enabled: json['enabled'] as bool? ?? false,
        chatModelId: json['chatModelId'] as String?,
        ocrModelId: json['ocrModelId'] as String?,
        ocrPrompt: json['ocrPrompt'] as String?,
        asrModelId: json['asrModelId'] as String?,
        ttsModelId: json['ttsModelId'] as String?,
        embeddingModelId: json['embeddingModelId'] as String?,
        rerankModelId: json['rerankModelId'] as String?,
        securityModelId: json['securityModelId'] as String?,
      );

  /// 从 shared_preferences 读取（无记录时返回默认关闭配置）
  static Future<CooperationConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return CooperationConfig();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return CooperationConfig.fromJson(decoded);
      }
    } catch (_) {
      // 配置损坏时回退默认值
    }
    return CooperationConfig();
  }

  /// 持久化到 shared_preferences
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(toJson()));
  }
}

/// 合作系统门面（应用级单例，GetX Service）。
///
/// 职责：
/// - 持有并持久化 [CooperationConfig]
/// - 提供按角色解析「已下载模型 → 本地路径 + 投影器路径」的能力
/// - 暴露各阶段执行方法（OCR / ASR / TTS / 安全审核 / 向量 / 重排），
///   全部走 LlamaService 的自包含执行（load → run → dispose），
///   与群聊共享「同一时刻仅一个模型驻留内存」约束
class CooperationService extends GetxService {
  static CooperationService get to => Get.find<CooperationService>();

  final config = CooperationConfig().obs;

  Future<CooperationService> init() async {
    config.value = await CooperationConfig.load();
    return this;
  }

  /// 保存配置（UI 层调用）
  Future<void> updateConfig(CooperationConfig next) async {
    config.value = next;
    await next.save();
  }

  /// 已下载且具备指定能力的模型列表（角色选择器用）
  List<AiModel> downloadedModelsFor(PipelineRole role) {
    final capability = role.requiredCapability;
    return ModelRepository.to.models
        .where((m) => StorageService.to.pathFor(m.id) != null)
        .where((m) => m.hasCapability(capability))
        .toList();
  }

  /// 解析角色对应的本地模型；返回 (模型, 主文件路径, 投影器路径或 null)。
  /// 未配置 / 未下载 / 模型不存在时返回 null。
  ({AiModel model, String path, String? projectorPath})? resolveRole(
    PipelineRole role,
  ) {
    final id = config.value.modelIdFor(role);
    if (id == null) return null;
    final model = ModelRepository.to.byId(id);
    final path = StorageService.to.pathFor(id);
    if (model == null || path == null) return null;
    return (model: model, path: path, projectorPath: StorageService.to.projectorPathFor(id));
  }

  /// 主对话模型（合作开启时聊天页应使用的模型）
  ({AiModel model, String path, String? projectorPath})? get primaryChatModel =>
      resolveRole(PipelineRole.chat);

  // ---------- 各阶段执行（严格串行：load → execute → dispose） ----------

  /// OCR 阶段：图片 → 文本（自动回退链 + 3 天结果缓存）。
  ///
  /// 回退链（对齐 RikkaHub 的「聊天模型不支持视觉 → 指定模型自动 OCR」机制，
  /// 并针对本地推理场景扩展）：
  /// 1. 桌面端且配置了 OCR 角色模型 → 视觉模型 OCR（提示词可配置）
  /// 2. 移动端 → ML Kit 设备端离线 OCR（视觉模型引擎不支持图像输入）
  ///
  /// 结果按「图片内容 + 提示词」缓存 3 天，重复发送不重复识别。
  Future<String?> runOcr(String imagePath) async {
    final prompt = config.value.effectiveOcrPrompt;

    // 缓存命中：直接复用
    try {
      final cached = await OcrCache.get(imagePath, prompt);
      if (cached != null) return cached;
    } catch (_) {}

    String? text;
    // 1. 视觉模型 OCR（仅桌面端引擎支持图像输入）
    if (LlamaService.supportsMultimodal) {
      try {
        text = await _runVisionModelOcr(imagePath, prompt);
      } on UnsupportedError {
        text = null;
      }
    }
    // 2. 设备端 ML Kit OCR（移动端离线兜底）
    text ??= await OcrService.instance.recognizeFile(imagePath);

    if (text != null && text.trim().isNotEmpty) {
      try {
        await OcrCache.put(imagePath, prompt, text.trim());
      } catch (_) {}
      return text.trim();
    }
    return null;
  }

  /// 视觉模型执行 OCR（自包含：load → generate → dispose）
  Future<String?> _runVisionModelOcr(String imagePath, String prompt) async {
    final role = resolveRole(PipelineRole.ocr);
    if (role == null) return null;
    final loaded = await LlamaService.instance.loadModel(
      role.path,
      projectorPath: role.projectorPath,
    );
    if (!loaded) return null;
    try {
      final buffer = StringBuffer();
      await for (final chunk in LlamaService.instance.generateChatStreamWithMedia(
        [
          LlamaTurn(role: 'user', content: prompt, imagePaths: [imagePath]),
        ],
        temperature: 0.1,
        maxTokens: 4096,
      )) {
        buffer.write(chunk);
      }
      return buffer.toString().trim();
    } finally {
      await LlamaService.instance.dispose();
    }
  }

  /// OCR 通道是否可用（移动端 ML Kit 恒可用；桌面端需配置 OCR 模型）。
  /// 聊天页据此放行图片附件（纯文本模型也能收图：先 OCR 转文字）。
  bool get ocrAvailable =>
      OcrService.isSupported ||
      resolveRole(PipelineRole.ocr) != null;

  /// ASR 阶段：音频文件 → 文本。
  Future<String?> runAsr(String audioPath) async {
    final role = resolveRole(PipelineRole.asr);
    if (role == null) return null;
    return LlamaService.instance.transcribeAudio(
      role.path,
      audioPath,
      projectorPath: role.projectorPath,
    );
  }

  /// TTS 阶段：文本 → PCM 音频。
  Future<TtsAudio?> runTts(String text, {String language = 'zh'}) async {
    final role = resolveRole(PipelineRole.tts);
    if (role == null) return null;
    return LlamaService.instance.synthesizeSpeech(
      role.path,
      text,
      projectorPath: role.projectorPath,
      language: language,
    );
  }

  /// 向量阶段：文本 → 向量（L2 归一化）。
  Future<List<double>?> runEmbedding(String text) async {
    final role = resolveRole(PipelineRole.embedding);
    if (role == null) return null;
    return LlamaService.instance.embedText(role.path, text);
  }

  /// 重排阶段：候选文档按查询相关性打分（0-10），返回降序排列的文档索引。
  ///
  /// 未配置重排模型时保持原顺序。
  Future<List<int>> runRerank(String query, List<String> documents) async {
    final order = List<int>.generate(documents.length, (i) => i);
    final role = resolveRole(PipelineRole.rerank);
    if (role == null || documents.isEmpty) return order;
    final loaded = await LlamaService.instance.loadModel(role.path);
    if (!loaded) return order;
    try {
      final scores = <double>[];
      for (final doc in documents) {
        final buffer = StringBuffer();
        await for (final chunk in LlamaService.instance.generateChatStream(
          [
            LlamaTurn(
              role: 'user',
              content:
                  'Rate how relevant the document is to the query on a scale '
                  'of 0 to 10. Reply with a single number only.\n'
                  'Query: $query\nDocument: $doc',
            ),
          ],
          temperature: 0.1,
          maxTokens: 8,
        )) {
          buffer.write(chunk);
        }
        scores.add(double.tryParse(buffer.toString().trim()) ?? 0);
      }
      // 稳定降序：分数相同保持原相对顺序
      final indexed = List.generate(documents.length, (i) => i);
      indexed.sort((a, b) {
        final cmp = scores[b].compareTo(scores[a]);
        return cmp != 0 ? cmp : a.compareTo(b);
      });
      return indexed;
    } finally {
      await LlamaService.instance.dispose();
    }
  }

  /// 安全审核：内容是否安全。未配置安全模型时默认放行。
  Future<({bool safe, String reason})> runSecurityCheck(String text) async {
    final role = resolveRole(PipelineRole.security);
    if (role == null) return (safe: true, reason: '');
    final loaded = await LlamaService.instance.loadModel(role.path);
    if (!loaded) return (safe: true, reason: '');
    try {
      final buffer = StringBuffer();
      await for (final chunk in LlamaService.instance.generateChatStream(
        [
          LlamaTurn(
            role: 'user',
            content:
                'Task: Check if there is unsafe content in the following text '
                'according to the safety policy (violent crimes, non-violent crimes, '
                'sex crimes, child exploitation, defamation, specialized advice, '
                'privacy, intellectual property, indiscriminate weapons, hate, '
                'self-harm, sexual content, elections).\n'
                'Reply with "safe" or "unsafe" on the first line only.\n\n'
                'Text: $text',
          ),
        ],
        temperature: 0.1,
        maxTokens: 64,
      )) {
        buffer.write(chunk);
      }
      final output = buffer.toString().toLowerCase();
      if (output.contains('unsafe')) {
        return (safe: false, reason: buffer.toString().trim());
      }
      return (safe: true, reason: '');
    } finally {
      await LlamaService.instance.dispose();
    }
  }
}
