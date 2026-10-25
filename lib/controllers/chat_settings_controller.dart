import 'dart:convert';

import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 模型高级推理参数（对标 MNN Chat 的模型设置）
///
/// - [contextSize] 上下文长度（KV cache 预算），可选 1024 / 2048 / 4096
/// - [systemPrompt] 系统提示词，每轮请求前置
/// - [temperature] 采样温度（发散度），0.0 ~ 1.5
/// - [threads] 推理线程数
///
/// 参数持久化于 shared_preferences，供 ChatController 热重载与生成时读取。
class ChatSettingsController extends GetxController {
  ChatSettingsController._();

  static final ChatSettingsController instance = ChatSettingsController._();

  static const String _prefsKey = 'chat_settings_v1';

  /// 可选的上下文长度档位
  static const List<int> contextSizeOptions = <int>[1024, 2048, 4096];

  /// 推荐默认值（同时是【恢复默认】的目标）
  static const int defaultContextSize = 2048;
  static const String defaultSystemPrompt = '你是一个诚实的中文助理';
  static const double defaultTemperature = 0.7;
  static const int defaultThreads = 4;

  final contextSize = defaultContextSize.obs;
  final systemPrompt = defaultSystemPrompt.obs;
  final temperature = defaultTemperature.obs;
  final threads = defaultThreads.obs;

  SharedPreferences? _prefs;

  /// 初始化：读取本地持久化参数（无记录则用默认值）
  Future<ChatSettingsController> init() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs?.getString(_prefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        contextSize.value = _clampContextSize(json['contextSize'] as int?);
        systemPrompt.value = json['systemPrompt'] as String? ?? defaultSystemPrompt;
        temperature.value = ((json['temperature'] as num?) ?? defaultTemperature)
            .clamp(0.0, 1.5)
            .toDouble();
        threads.value = ((json['threads'] as int?) ?? defaultThreads).clamp(1, 8);
      } catch (_) {
        // 数据损坏：静默回退默认值，下次保存会覆盖
      }
    }
    return this;
  }

  static int _clampContextSize(int? value) =>
      contextSizeOptions.contains(value) ? value! : defaultContextSize;

  /// 当前是否全部为推荐默认值
  bool get isDefault =>
      contextSize.value == defaultContextSize &&
      systemPrompt.value == defaultSystemPrompt &&
      temperature.value == defaultTemperature &&
      threads.value == defaultThreads;

  /// 保存参数（持久化；是否触发热重载由调用方决定）
  Future<void> save({
    required int contextSize,
    required String systemPrompt,
    required double temperature,
    required int threads,
  }) async {
    this.contextSize.value = _clampContextSize(contextSize);
    this.systemPrompt.value = systemPrompt.trim().isEmpty
        ? defaultSystemPrompt
        : systemPrompt.trim();
    this.temperature.value = temperature.clamp(0.0, 1.5).toDouble();
    this.threads.value = threads.clamp(1, 8);
    await _persist();
  }

  /// 一键恢复推荐默认值（持久化）
  Future<void> resetDefaults() async {
    contextSize.value = defaultContextSize;
    systemPrompt.value = defaultSystemPrompt;
    temperature.value = defaultTemperature;
    threads.value = defaultThreads;
    await _persist();
  }

  /// OOM 降级专用：仅把上下文长度改为 2048 并持久化，不动其余参数
  Future<void> downgradeContextSizeToSafe() async {
    if (contextSize.value == defaultContextSize) return;
    contextSize.value = defaultContextSize;
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    await prefs.setString(
      _prefsKey,
      jsonEncode({
        'contextSize': contextSize.value,
        'systemPrompt': systemPrompt.value,
        'temperature': temperature.value,
        'threads': threads.value,
      }),
    );
  }
}
