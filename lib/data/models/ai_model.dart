import 'download_source.dart';

/// 模型能力标签（合作系统角色分配 / 群聊成员筛选的依据）。
///
/// 与 [ModelCategory]（商店顶部旧四分筛选）不同，能力是**可叠加**的：
/// 一个多模态模型可同时具备 vision + ocr + chat。
/// 商店 JSON 的 `capabilities` 字段显式声明；缺失时按 domain/vertical/tags 推导。
enum ModelCapability {
  chat('对话', '通用文本对话'),
  vision('视觉', '图像理解 / 视觉问答'),
  ocr('OCR', '图片文字提取'),
  asr('语音识别', '语音转文字'),
  tts('语音合成', '文字转语音'),
  embedding('向量', '文本向量化 / RAG'),
  rerank('重排', '检索结果重排序'),
  security('安全审核', '内容安全分类'),
  code('代码', '代码生成'),
  reasoning('推理', '数理逻辑 / 思维链');

  const ModelCapability(this.label, this.hint);

  /// 能力标签文案（UI Chip 用）
  final String label;

  /// 能力说明文案
  final String hint;

  /// 由 JSON 字符串解析（未知值返回 null）
  static ModelCapability? fromName(String? name) {
    if (name == null) return null;
    for (final c in ModelCapability.values) {
      if (c.name == name) return c;
    }
    return null;
  }
}

/// 商店顶部筛选分类（由 domain/vertical 推导，兼容旧 UI）
enum ModelCategory {
  standard('标准', '通用对话 · 轻量流畅'),
  reasoning('推理', '逻辑数理 · 深度思考'),
  vertical('垂直', '行业场景 · 开箱即用'),
  multimodal('多模态', '图文理解 · 视觉问答');

  const ModelCategory(this.label, this.hint);

  /// 筛选标签文案
  final String label;

  /// 分类说明文案
  final String hint;
}

/// 模型架构格式（决定底层推理引擎路由）
enum ModelFormat {
  /// GGUF：llama.cpp 生态，当前唯一已接入的引擎
  gguf('GGUF'),

  /// MNN：阿里巴巴移动端推理引擎（适配中）
  mnn('MNN'),

  /// LiteRT：Google LiteRT / MediaPipe（适配中）
  litert('LiteRT'),

  /// Apple Core ML 模型（适配中）
  apple('Apple');

  const ModelFormat(this.label);

  /// 展示标签（筛选 Chip / 架构标签用）
  final String label;

  /// 由文件后缀推断架构（导入本地模型时兜底用）
  static ModelFormat fromExtension(String ext) {
    switch (ext.toLowerCase()) {
      case '.mnn':
        return ModelFormat.mnn;
      case '.litertlm':
      case '.tflite':
        return ModelFormat.litert;
      case '.mlmodel':
      case '.mlpackage':
        return ModelFormat.apple;
      default:
        return ModelFormat.gguf;
    }
  }
}

/// 一个本地模型（商店或已下载）
/// 数据来自 assets/store_data.json，不在 Dart 中硬编码
class AiModel {
  const AiModel({
    required this.id,
    required this.name,
    required this.author,
    required this.params,
    required this.sizeInGB,
    required this.quant,
    required this.tags,
    required this.colorIndex,
    required this.vendor,
    required this.domain,
    required this.vertical,
    required this.license,
    required this.githubStars,
    this.description = '',
    this.downloadUrl,
    this.chatTemplate,
    this.githubRepo,
    this.format = ModelFormat.gguf,
    this.capabilities = const <ModelCapability>[],
    this.projectorUrl,
    this.projectorSizeMB = 0,
  });

  /// 唯一标识（仓库+文件名生成的 slug，同时用作本地文件名）
  final String id;

  /// 模型名称
  final String name;

  /// 来源 / 作者
  final String author;

  /// 参数量，如 3B
  final String params;

  /// 文件体积（GB），如 1.96
  final double sizeInGB;

  /// 量化方式，如 Q4_K_M
  final String quant;

  /// 标签
  final List<String> tags;

  /// 头像渐变色索引
  final int colorIndex;

  /// 厂商，如 阿里云 Qwen
  final String vendor;

  /// 领域：文本 / 多模态 / 全模态 / 音乐 / 图像 / 视频
  final String domain;

  /// 垂直分类：通用 / 医疗 / 金融 / 数学 / 代码 / 法律 等
  final String vertical;

  /// 开源协议，如 Apache 2.0 / MIT
  final String license;

  /// GitHub 星数（本地缓存值，启动时异步刷新）
  final int githubStars;

  /// 简介
  final String description;

  /// GGUF 直链下载地址（hf-mirror.com 镜像）
  final String? downloadUrl;

  /// 该模型可用的下载源列表（按主链接域名派生，始终含「手动上传」）。
  /// 纯派生，不改数据文件，远端 JSON 缓存天然兼容。
  List<DownloadSource> get availableSources => availableSourcesFor(downloadUrl);

  /// 指定下载源对应的主文件下载地址；手动上传或不适用时返回 null。
  String? urlFor(DownloadSource source) => resolveUrl(downloadUrl, source);

  /// 指定下载源对应的投影器地址（与主源同 host，保证官方/镜像不混用）。
  String? projectorUrlFor(DownloadSource source) =>
      resolveUrl(projectorUrl, source);

  /// llama.cpp 聊天模板：chatml / llama2 / alpaca / vicuna / phi / gemma / zephyr
  final String? chatTemplate;

  /// GitHub 仓库（owner/repo），用于远程同步星数
  final String? githubRepo;

  /// 模型架构格式（默认 GGUF；商店数据未提供时按 GGUF 处理）
  final ModelFormat format;

  /// 能力标签（合作系统 / 群聊角色分配用）。
  /// 为空时按 [effectiveCapabilities] 从 domain/vertical/tags 推导。
  final List<ModelCapability> capabilities;

  /// 多模态投影器（mmproj）下载地址。
  /// OCR / ASR / TTS 类模型除主 GGUF 外还需配套投影器才能运行。
  final String? projectorUrl;

  /// 投影器文件体积（MB），仅用于展示与下载进度估算。
  final int projectorSizeMB;

  /// 展示用体积文案，如 "1.96 GB"；带投影器时附注投影器体积
  String get sizeLabel {
    final base = '${sizeInGB.toStringAsFixed(2)} GB';
    if (needsProjector && projectorSizeMB > 0) {
      return '$base + 投影器 $projectorSizeMB MB';
    }
    return base;
  }

  /// 是否需要配套投影器（多模态/语音类模型）
  bool get needsProjector => projectorUrl != null && projectorUrl!.isNotEmpty;

  /// 生效的能力列表：JSON 显式声明优先，否则按元数据推导
  List<ModelCapability> get effectiveCapabilities {
    if (capabilities.isNotEmpty) return capabilities;
    return _deriveCapabilities();
  }

  /// 是否具备某能力（按生效能力判断）
  bool hasCapability(ModelCapability c) => effectiveCapabilities.contains(c);

  /// 按 domain/vertical/tags 推导能力（商店数据未声明时的兜底）
  List<ModelCapability> _deriveCapabilities() {
    final result = <ModelCapability>{};
    final tagsLower = tags.map((t) => t.toLowerCase()).toSet();
    final nameLower = name.toLowerCase();

    // 文本类模型默认具备对话能力
    if (domain == '文本' || domain == '多模态' || domain == '全模态') {
      result.add(ModelCapability.chat);
    }
    if (domain == '多模态' || domain == '全模态' || domain == '图像') {
      result.add(ModelCapability.vision);
    }
    if (tagsLower.any((t) => t.contains('ocr'))) {
      result.add(ModelCapability.ocr);
    }
    if (tagsLower.any((t) => t.contains('语音识别') || t.contains('asr'))) {
      result.add(ModelCapability.asr);
    }
    if (tagsLower.any((t) => t.contains('语音合成') || t.contains('tts'))) {
      result.add(ModelCapability.tts);
    }
    if (tagsLower.any((t) => t.contains('embedding') || t.contains('向量'))) {
      result.add(ModelCapability.embedding);
    }
    if (tagsLower.any((t) => t.contains('rerank') || t.contains('重排'))) {
      result.add(ModelCapability.rerank);
    }
    if (tagsLower.any(
          (t) => t.contains('安全') || t.contains('审核') || t.contains('guard'),
        ) ||
        nameLower.contains('guard')) {
      result.add(ModelCapability.security);
    }
    if (vertical == '代码' || tagsLower.any((t) => t.contains('代码'))) {
      result.add(ModelCapability.code);
    }
    if (vertical == '数学' || tagsLower.any((t) => t.contains('推理'))) {
      result.add(ModelCapability.reasoning);
    }
    return result.toList();
  }

  /// 由领域/垂直推导出的旧版四分分类（供兼容 UI 使用）
  ModelCategory get category {
    switch (domain) {
      case '多模态':
      case '全模态':
      case '图像':
      case '视频':
      case '音乐':
        return ModelCategory.multimodal;
      case '文本':
        if (vertical == '通用') return ModelCategory.standard;
        return vertical == '数学' ? ModelCategory.reasoning : ModelCategory.vertical;
      default:
        return ModelCategory.vertical;
    }
  }

  AiModel copyWith({int? githubStars}) => AiModel(
        id: id,
        name: name,
        author: author,
        params: params,
        sizeInGB: sizeInGB,
        quant: quant,
        tags: tags,
        colorIndex: colorIndex,
        vendor: vendor,
        domain: domain,
        vertical: vertical,
        license: license,
        githubStars: githubStars ?? this.githubStars,
        description: description,
        downloadUrl: downloadUrl,
        chatTemplate: chatTemplate,
        githubRepo: githubRepo,
        format: format,
        capabilities: capabilities,
        projectorUrl: projectorUrl,
        projectorSizeMB: projectorSizeMB,
      );

  factory AiModel.fromJson(Map<String, dynamic> json) => AiModel(
        id: json['id'] as String,
        name: json['name'] as String,
        author: json['author'] as String? ?? json['vendor'] as String? ?? '',
        params: json['params'] as String? ?? '',
        sizeInGB: (json['sizeInGB'] as num?)?.toDouble() ?? 0,
        quant: json['quant'] as String? ?? 'Q4_K_M',
        tags: (json['tags'] as List?)?.whereType<String>().toList() ?? const [],
        colorIndex: (json['colorIndex'] as num?)?.toInt() ?? 0,
        vendor: json['vendor'] as String? ?? '',
        domain: json['domain'] as String? ?? '文本',
        vertical: json['vertical'] as String? ?? '通用',
        license: json['license'] as String? ?? '',
        githubStars: (json['githubStars'] as num?)?.toInt() ?? 0,
        description: json['description'] as String? ?? '',
        downloadUrl: json['downloadUrl'] as String?,
        chatTemplate: json['chatTemplate'] as String?,
        githubRepo: json['githubRepo'] as String?,
        format: ModelFormat.values.firstWhere(
          (f) => f.name == json['format'] || f.label == json['format'],
          orElse: () => ModelFormat.gguf,
        ),
        capabilities: (json['capabilities'] as List?)
                ?.map((e) => ModelCapability.fromName(e as String?))
                .whereType<ModelCapability>()
                .toList() ??
            const <ModelCapability>[],
        projectorUrl: json['projectorUrl'] as String?,
        projectorSizeMB: (json['projectorSizeMB'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'author': author,
        'params': params,
        'sizeInGB': sizeInGB,
        'quant': quant,
        'tags': tags,
        'colorIndex': colorIndex,
        'vendor': vendor,
        'domain': domain,
        'vertical': vertical,
        'license': license,
        'githubStars': githubStars,
        'description': description,
        'downloadUrl': downloadUrl,
        'chatTemplate': chatTemplate,
        'githubRepo': githubRepo,
        'format': format.name,
        'capabilities': capabilities.map((c) => c.name).toList(),
        'projectorUrl': projectorUrl,
        'projectorSizeMB': projectorSizeMB,
      };
}
