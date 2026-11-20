import 'dart:convert';

import 'package:dio/dio.dart';

import '../config/app_config.dart';

/// 远端版本信息（[AppConfig.updateUrls] 指向的 JSON 结构）
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.releaseNotes,
  });

  final String version;
  final String downloadUrl;
  final String releaseNotes;
}

/// 检查更新结果：info 与 reason 二选一
class UpdateCheckResult {
  const UpdateCheckResult({this.info, this.reason});

  final UpdateInfo? info;

  /// 失败原因（可直接展示给用户）
  final String? reason;

  bool get ok => info != null;
}

/// 检查更新服务：多源回退拉取版本 JSON 并与本地版本比较
class UpdateChecker {
  UpdateChecker._();

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: AppConfig.updateCheckTimeout,
      receiveTimeout: AppConfig.updateCheckTimeout,
      // CNB 的 404 会返回 HTML 但状态码 200：靠 JSON 解析失败兜底
      responseType: ResponseType.plain,
    ),
  );

  /// 拉取远端版本信息：逐源尝试，全部失败时返回带原因的结果
  static Future<UpdateCheckResult> check() async {
    // 更新源尚未配置（占位符未替换）：给出可行动的提示而非笼统"网络异常"
    if (!AppConfig.remoteConfigured) {
      return const UpdateCheckResult(reason: '更新源尚未配置：等待代码仓库创建后自动生效');
    }
    for (final url in AppConfig.updateUrls) {
      try {
        final response = await _dio.get<String>(url);
        final raw = response.data;
        if (raw == null || raw.isEmpty) continue;
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final version = json['version'] as String?;
        final downloadUrl = json['download_url'] as String?;
        if (version == null || version.isEmpty) continue;
        if (downloadUrl == null || downloadUrl.isEmpty) continue;
        return UpdateCheckResult(
          info: UpdateInfo(
            version: version,
            downloadUrl: downloadUrl,
            releaseNotes: json['release_notes'] as String? ?? '',
          ),
        );
      } catch (_) {
        continue; // 当前源不可达（被墙/404/超时）：切下一源
      }
    }
    return const UpdateCheckResult(reason: '所有更新源均不可达（网络受限或稍后再试）');
  }

  /// 兼容旧接口：只取结果
  static Future<UpdateInfo?> fetch() async => (await check()).info;

  /// 语义化版本比较：远端版本高于本地返回 true
  /// 兼容 'v' 前缀与非数字段（如 1.2.0-beta 按 1.2.0 处理）
  static bool isNewer(String remote, String current) {
    final r = _parse(remote);
    final c = _parse(current);
    for (var i = 0; i < 3; i++) {
      if (r[i] != c[i]) return r[i] > c[i];
    }
    return false;
  }

  static List<int> _parse(String version) {
    final cleaned = version.trim().replaceFirst(RegExp(r'^[vV]'), '');
    final parts = cleaned.split(RegExp(r'[.\-+]'));
    final nums = <int>[];
    for (final part in parts.take(3)) {
      nums.add(int.tryParse(part) ?? 0);
    }
    while (nums.length < 3) {
      nums.add(0);
    }
    return nums;
  }
}
