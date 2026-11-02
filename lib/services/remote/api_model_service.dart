import 'dart:convert';

import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一个导入的远程 API 模型（OpenAI 兼容 /chat/completions）
class ApiModelConfig {
  ApiModelConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  /// 本地唯一 id（聊天记录以 api:<id> 作为 modelId 持久化）
  final String id;
  String name;
  String baseUrl;
  String apiKey;

  /// 请求体里的 model 字段（如 deepseek-chat、gpt-4o-mini）
  String model;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'model': model,
  };

  static ApiModelConfig fromJson(Map<String, dynamic> json) => ApiModelConfig(
        id: _str(json['id'], ''),
        name: _str(json['name'], 'API 模型'),
        baseUrl: _str(json['baseUrl'], ''),
        apiKey: _str(json['apiKey'], ''),
        model: _str(json['model'], ''),
      );

  /// 容错取值：非字符串值（损坏数据）安全转为字符串
  static String _str(Object? value, String fallback) {
    if (value == null) return fallback;
    if (value is String) return value;
    return value.toString();
  }

  /// API key 打码展示（sk-ab...ef9）
  String get maskedKey {
    if (apiKey.isEmpty) return '未设置密钥';
    if (apiKey.length <= 8) return '${apiKey.substring(0, 2)}****';
    return '${apiKey.substring(0, 5)}...${apiKey.substring(apiKey.length - 3)}';
  }
}

/// 导入的 API 模型集合（shared_preferences 持久化）
class ApiModelService extends GetxService {
  ApiModelService._();

  static final ApiModelService instance = ApiModelService._();

  static ApiModelService get to => Get.find();

  static const String _prefsKey = 'api_models_v1';

  final configs = <ApiModelConfig>[].obs;

  SharedPreferences? _prefs;

  Future<ApiModelService> init() async {
    _prefs = await SharedPreferences.getInstance();
    _load();
    return this;
  }

  void _load() {
    final raw = _prefs?.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List;
      configs
        ..clear()
        ..addAll(
          list
              .whereType<Map>()
              .map((m) => ApiModelConfig.fromJson(m.cast<String, dynamic>()))
              .toList(),
        );
    } catch (_) {
      // 数据损坏：忽略，保留空列表
    }
  }

  Future<void> _persist() async {
    await _prefs?.setString(
      _prefsKey,
      jsonEncode(configs.map((c) => c.toJson()).toList()),
    );
  }

  ApiModelConfig? byId(String id) {
    for (final c in configs) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<ApiModelConfig> add({
    required String name,
    required String baseUrl,
    required String apiKey,
    required String model,
  }) async {
    final config = ApiModelConfig(
      id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      name: name.trim().isEmpty ? model.trim() : name.trim(),
      baseUrl: baseUrl.trim(),
      apiKey: apiKey.trim(),
      model: model.trim(),
    );
    configs.add(config);
    await _persist();
    return config;
  }

  Future<void> update(ApiModelConfig config) async {
    await _persist();
  }

  Future<void> remove(String id) async {
    configs.removeWhere((c) => c.id == id);
    await _persist();
  }
}
