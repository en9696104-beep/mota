import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../data/models/ai_model.dart';

/// 模型目录仓库：三级数据源加载全部模型
///
/// 1. **远程**：启动时请求 [AppConfig.storeDataUrl]（GitHub Raw 假服务器），
///    成功则覆盖写入本地缓存并使用
/// 2. **远程缓存**：断网/失败时读取上次远程成功缓存的数据
/// 3. **内置**：最终兜底，读取 assets/store_data.json
///
/// 另用 shared_preferences 缓存 GitHub 星数（断网时回退本地值）
class ModelRepository extends GetxService {
  static ModelRepository get to => Get.find<ModelRepository>();

  static const _starsCacheKey = 'github_stars_cache_v1';

  /// 全部商店模型
  final RxList<AiModel> models = <AiModel>[].obs;

  /// 数据是否加载完成
  final RxBool loaded = false.obs;

  /// 当前数据来源：远程 / 远程缓存 / 本地内置（设置页展示用）
  final RxString dataSource = '本地内置'.obs;

  Future<ModelRepository> init() async {
    final prefs = await SharedPreferences.getInstance();
    List<AiModel>? list;
    var source = '本地内置';

    // 1. 远端拉取（多源回退：CNB → Gitee → GitHub Raw）；
    //    源未配置（<OWNER> 未替换）时跳过，零等待直接走本地
    if (AppConfig.remoteConfigured) {
      for (final url in AppConfig.storeDataUrls) {
        try {
          final response = await Dio()
              .get<String>(
                url,
                options: Options(responseType: ResponseType.plain),
              )
              .timeout(AppConfig.storeFetchTimeout);
          final raw = response.data;
          final parsed = _parseModels(raw);
          if (parsed != null && parsed.isNotEmpty) {
            list = parsed;
            source = '远程';
            await prefs.setString(AppConfig.storeDataCacheKey, raw!);
            break;
          }
        } catch (_) {
          continue; // 当前源不可达：切下一源
        }
      }
    }

    // 2. 本地缓存（上次远程成功拉取的数据）
    if (list == null) {
      final cached = prefs.getString(AppConfig.storeDataCacheKey);
      final parsed = _parseModels(cached);
      if (parsed != null && parsed.isNotEmpty) {
        list = parsed;
        source = '远程缓存';
      }
    }

    // 3. assets 内置（最终兜底）
    list ??= _parseModels(
      await rootBundle.loadString('assets/store_data.json'),
    )!;

    final cached = prefs.getString(_starsCacheKey);
    if (cached != null && cached.isNotEmpty) {
      try {
        final map = (jsonDecode(cached) as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, (v as num).toInt()),
        );
        for (var i = 0; i < list.length; i++) {
          final repo = list[i].githubRepo;
          if (repo != null && map.containsKey(repo)) {
            list[i] = list[i].copyWith(githubStars: map[repo]);
          }
        }
      } catch (_) {
        // 缓存损坏时忽略，使用 JSON 内置值
      }
    }
    models.assignAll(list);
    dataSource.value = source;
    loaded.value = true;
    return this;
  }

  /// 解析模型列表 JSON；格式不符返回 null（调用方走下一级数据源）
  static List<AiModel>? _parseModels(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(AiModel.fromJson)
          .toList();
    } catch (_) {
      return null;
    }
  }

  AiModel? byId(String id) {
    for (final m in models) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// 按模型名查找（历史会话按名称反查模型用）
  AiModel? byName(String name) {
    for (final m in models) {
      if (m.name == name) return m;
    }
    return null;
  }

  /// 用远程拉到的星数更新内存与本地缓存
  Future<void> updateStars(Map<String, int> repoStars) async {
    if (repoStars.isEmpty) return;
    var changed = false;
    for (var i = 0; i < models.length; i++) {
      final repo = models[i].githubRepo;
      if (repo == null) continue;
      final stars = repoStars[repo];
      if (stars != null && stars != models[i].githubStars) {
        models[i] = models[i].copyWith(githubStars: stars);
        changed = true;
      }
    }
    if (!changed) return;
    models.refresh();
    final prefs = await SharedPreferences.getInstance();
    final current = <String, int>{};
    for (final m in models) {
      if (m.githubRepo != null) current[m.githubRepo!] = m.githubStars;
    }
    await prefs.setString(_starsCacheKey, jsonEncode(current));
  }
}
