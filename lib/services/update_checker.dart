import 'dart:convert';

import 'package:dio/dio.dart';

import '../config/app_config.dart';

/// 远端版本信息（[AppConfig.updateUrl] 指向的 JSON 结构）
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

/// 检查更新服务：拉取 GitHub Raw 上的版本 JSON 并与本地版本比较
class UpdateChecker {
  UpdateChecker._();

  /// 拉取远端版本信息；网络异常 / 格式不符返回 null
  static Future<UpdateInfo?> fetch() async {
    try {
      final response = await Dio()
          .get<String>(
            AppConfig.updateUrl,
            options: Options(responseType: ResponseType.plain),
          )
          .timeout(AppConfig.updateCheckTimeout);
      final raw = response.data;
      if (raw == null || raw.isEmpty) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final version = json['version'] as String?;
      final downloadUrl = json['download_url'] as String?;
      if (version == null || version.isEmpty) return null;
      if (downloadUrl == null || downloadUrl.isEmpty) return null;
      return UpdateInfo(
        version: version,
        downloadUrl: downloadUrl,
        releaseNotes: json['release_notes'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }

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
