import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本地存储服务
/// - 持久化「已下载模型 id → 本地 GGUF 文件路径」映射（shared_preferences）
/// - 管理模型统一存放目录 <app documents>/models
/// - 持久化「自定义导入模型」的完整元数据（含架构 format）
class StorageService extends GetxService {
  static StorageService get to => Get.find<StorageService>();

  late final SharedPreferences _prefs;

  /// prefs 键：List<String>，每项格式 "id|path"
  static const String _kEntries = 'downloaded_entries';

  /// prefs 键：自定义导入模型的元数据 JSON 列表（不在商店目录中的模型）
  static const String _kImportedModels = 'imported_models_v1';

  Future<StorageService> init() async {
    _prefs = await SharedPreferences.getInstance();
    return this;
  }

  /// 已下载模型 id 列表（按下载顺序）
  List<String> get downloadedIds => _prefs
          .getStringList(_kEntries)
          ?.map((entry) => entry.split('|').first)
          .toList() ??
      const <String>[];

  /// 查询某个模型的本地文件路径，未下载返回 null
  String? pathFor(String id) {
    final entries = _prefs.getStringList(_kEntries) ?? const <String>[];
    for (final entry in entries) {
      final parts = entry.split('|');
      if (parts.length == 2 && parts[0] == id) return parts[1];
    }
    return null;
  }

  /// 查询某个模型的投影器（mmproj）本地路径；未配置或文件不存在返回 null
  String? projectorPathFor(String id) {
    final path = pathFor(id);
    if (path == null) return null;
    // 主文件为 <id>.gguf 时投影器为 <id>.mmproj.gguf；
    // 自定义导入路径（无 .gguf 后缀）则拼 .mmproj.gguf
    final base = path.toLowerCase().endsWith('.gguf')
        ? path.substring(0, path.length - 5)
        : path;
    final candidate = '$base.mmproj.gguf';
    return File(candidate).existsSync() ? candidate : null;
  }

  /// 记录「已下载」（重复记录会先移除旧条目）
  Future<void> markDownloaded(String id, String path) async {
    final entries =
        (_prefs.getStringList(_kEntries) ?? <String>[]).toList();
    entries.removeWhere((entry) => entry.split('|').first == id);
    entries.add('$id|$path');
    await _prefs.setStringList(_kEntries, entries);
  }

  /// 移除「已下载」记录
  Future<void> removeDownload(String id) async {
    final entries =
        (_prefs.getStringList(_kEntries) ?? <String>[]).toList();
    entries.removeWhere((entry) => entry.split('|').first == id);
    await _prefs.setStringList(_kEntries, entries);
  }

  // ---------- 自定义导入模型元数据 ----------

  /// 全部自定义导入模型的元数据（JSON Map 列表）
  List<Map<String, dynamic>> get importedModels {
    final raw = _prefs.getStringList(_kImportedModels) ?? const <String>[];
    final result = <Map<String, dynamic>>[];
    for (final item in raw) {
      try {
        final decoded = jsonDecode(item);
        if (decoded is Map) {
          result.add(decoded.cast<String, dynamic>());
        }
      } catch (_) {
        // 单条损坏不影响其余条目
      }
    }
    return result;
  }

  /// 保存一条导入模型元数据（重复 id 先移除旧条目）
  Future<void> saveImportedModel(Map<String, dynamic> meta) async {
    final entries = (_prefs.getStringList(_kImportedModels) ?? <String>[]).toList();
    final id = meta['id'] as String?;
    entries.removeWhere((e) {
      try {
        final decoded = jsonDecode(e);
        return decoded is Map && decoded['id'] == id;
      } catch (_) {
        return false;
      }
    });
    entries.add(jsonEncode(meta));
    await _prefs.setStringList(_kImportedModels, entries);
  }

  /// 移除一条导入模型元数据
  Future<void> removeImportedModel(String id) async {
    final entries = (_prefs.getStringList(_kImportedModels) ?? <String>[]).toList();
    entries.removeWhere((e) {
      try {
        final decoded = jsonDecode(e);
        return decoded is Map && decoded['id'] == id;
      } catch (_) {
        return false;
      }
    });
    await _prefs.setStringList(_kImportedModels, entries);
  }

  /// 模型统一存放目录（不存在则创建）
  Future<Directory> modelsDir() async {
    final docDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${docDir.path}/models');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 某个模型下载完成后的本地路径：<models>/<id>.gguf
  Future<String> localPathFor(String id) async =>
      '${(await modelsDir()).path}/$id.gguf';

  /// 某个模型的多模态投影器（mmproj）本地路径：<models>/<id>.mmproj.gguf
  Future<String> localProjectorPathFor(String id) async =>
      '${(await modelsDir()).path}/$id.mmproj.gguf';

  /// 投影器是否已下载到本地
  Future<bool> hasProjector(String id) async =>
      File(await localProjectorPathFor(id)).existsSync();

  /// 主模型文件是否存在
  Future<bool> hasModelFile(String id) async =>
      File(await localPathFor(id)).existsSync();
}
