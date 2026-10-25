import 'dart:async';

import 'package:dio/dio.dart';

import 'model_repository.dart';

/// GitHub 星数远程同步：App 启动时异步刷新本地目录中的 githubStars。
/// - 请求 https://api.github.com/repos/{owner}/{repo} 的 stargazers_count
/// - 失败 / 断网 / 触发限流时静默退出，UI 继续使用本地缓存值
/// - 同步成功后写入 shared_preferences 缓存（见 ModelRepository.updateStars）
class GitHubStarsSyncService {
  GitHubStarsSyncService._();

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      headers: <String, dynamic>{
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'MOTA-App',
      },
    ),
  );

  /// 与目录中全部不重复的 GitHub 仓库同步星数（低频请求，避免触发匿名限流）
  static Future<void> sync() async {
    try {
      final repos = ModelRepository.to.models
          .map((m) => m.githubRepo)
          .whereType<String>()
          .where((r) => r.isNotEmpty)
          .toSet()
          .toList();
      if (repos.isEmpty) return;

      final stars = <String, int>{};
      for (final repo in repos) {
        try {
          final resp = await _dio.get<dynamic>(
            'https://api.github.com/repos/$repo',
          );
          final data = resp.data;
          if (data is Map && data['stargazers_count'] is int) {
            stars[repo] = data['stargazers_count'] as int;
          }
        } catch (_) {
          // 单个仓库失败（网络/限流/仓库不存在）不影响其他仓库
        }
      }
      if (stars.isNotEmpty) {
        await ModelRepository.to.updateStars(stars);
      }
    } catch (_) {
      // 整体失败：静默使用本地缓存
    }
  }
}
