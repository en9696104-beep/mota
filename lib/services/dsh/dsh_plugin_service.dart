import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dsh_manifest.dart';
import 'dsh_models.dart';
import 'dsh_runtime.dart';

/// DSH 插件管理服务。
///
/// 职责：
/// - 安装：本地目录 / 本地 zip / `github:owner/repo`（下载 codeload 归档）
/// - 解析清单并发现工具（QuickJS 沙箱内执行 apply(ctx)）
/// - 启用 / 停用 / 移除；SharedPreferences 持久化插件清单
/// - 为聊天层提供 [enabledTools] 与 [callTool]
///
/// 兼容范围（MVP）：注册工具的插件（defineTool / ctx.tools.register）。
/// 依赖宿主服务（fs / sandbox / model 等系统服务）的插件不在兼容范围内，
/// 安装时会解析失败并给出明确原因。
class DshPluginService extends GetxService {
  static DshPluginService get to => Get.find<DshPluginService>();

  static const String _prefsKey = 'dsh_plugins_v1';

  final plugins = <DshPlugin>[].obs;
  final installing = false.obs;
  String? lastError;

  Directory? _rootDir;

  Future<DshPluginService> init() async {
    await _ensureRootDir();
    await _loadInstalled();
    return this;
  }

  Future<void> _ensureRootDir() async {
    final docs = await getApplicationDocumentsDirectory();
    _rootDir = Directory('${docs.path}${Platform.pathSeparator}dsh_plugins');
    if (!_rootDir!.existsSync()) _rootDir!.createSync(recursive: true);
  }

  String get _rootPath => _rootDir?.path ?? 'dsh_plugins';

  Future<void> _loadInstalled() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      plugins.value = decoded
          .whereType<Map>()
          .map((m) => DshPlugin.fromJson(m.cast<String, dynamic>()))
          // 目录已被删除的插件自动清理
          .where((p) => Directory(p.dirPath).existsSync())
          .toList();
    } catch (_) {
      plugins.clear();
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(plugins.map((p) => p.toJson()).toList()),
    );
  }

  // ---------- 安装 ----------

  /// 从本地 zip 安装
  Future<DshPlugin> installFromZip(String zipPath) async {
    installing.value = true;
    try {
      final bytes = File(zipPath).readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);
      final dir = await _extractArchive(archive);
      return await _installFromDir(dir);
    } on DshPluginException {
      rethrow;
    } catch (e) {
      throw DshPluginException('解压插件包失败：$e');
    } finally {
      installing.value = false;
    }
  }

  /// 从本地目录安装
  Future<DshPlugin> installFromDirectory(String sourcePath) async {
    installing.value = true;
    try {
      final source = Directory(sourcePath);
      if (!source.existsSync()) {
        throw const DshPluginException('所选目录不存在');
      }
      final target = await _newPluginDir('import');
      _copyRecursive(source, target);
      return await _installFromDir(target);
    } on DshPluginException {
      rethrow;
    } catch (e) {
      throw DshPluginException('复制插件目录失败：$e');
    } finally {
      installing.value = false;
    }
  }

  /// 从 GitHub 仓库安装（支持 `github:owner/repo`、`owner/repo`、完整 URL）。
  /// 依次尝试 main / master 分支的 codeload 归档。
  Future<DshPlugin> installFromGithub(String spec) async {
    installing.value = true;
    try {
      var repo = spec.trim();
      if (repo.startsWith('github:')) repo = repo.substring(7);
      final uri = Uri.tryParse(repo);
      if (uri != null && uri.host.contains('github.com')) {
        // 完整 URL：github.com/owner/repo[/tree/branch]
        final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
        if (segments.length >= 2) {
          repo = segments[0] == 'tree'
              ? repo // 异常形态，交给后续解析
              : '${segments[0]}/${segments[1]}';
        }
      }
      final match = RegExp(r'^([\w.-]+)/([\w.-]+)$').firstMatch(repo);
      if (match == null) {
        throw const DshPluginException('仓库地址无效，示例：github:owner/repo');
      }
      final owner = match.group(1)!;
      final name = match.group(2)!.replaceAll(RegExp(r'\.git$'), '');

      Object? lastException;
      for (final branch in const ['main', 'master']) {
        final url = 'https://codeload.github.com/$owner/$name/zip/refs/heads/$branch';
        try {
          final response = await Dio().get<List<int>>(
            url,
            options: Options(responseType: ResponseType.bytes),
          );
          final data = response.data;
          if (data == null || data.isEmpty) continue;
          final archive = ZipDecoder().decodeBytes(data);
          final dir = await _extractArchive(archive);
          return await _installFromDir(dir);
        } on DioException catch (e) {
          lastException = e;
          if (e.response?.statusCode == 404) continue; // 分支不存在，试下一个
          throw DshPluginException('下载插件归档失败：${e.message ?? e.type.name}');
        }
      }
      throw DshPluginException(
        '下载失败：未找到 main / master 分支归档'
        '${lastException is DioException && lastException.response?.statusCode != null ? '（HTTP ${lastException.response!.statusCode}）' : ''}',
      );
    } on DshPluginException {
      rethrow;
    } finally {
      installing.value = false;
    }
  }

  /// 从已解压目录完成安装：解析清单 → 发现工具 → 去重入库
  Future<DshPlugin> _installFromDir(Directory dir) async {
    final manifest = DshManifestParser.parse(dir.path);
    final source = File(manifest.entryFile).readAsStringSync();

    final tools = await DshRuntime.instance.discoverTools(source);

    // 同 id 插件：先移除旧目录再覆盖
    final existing = plugins.where((p) => p.id == manifest.pluginId).toList();
    for (final old in existing) {
      try {
        Directory(old.dirPath).deleteSync(recursive: true);
      } catch (_) {}
      plugins.remove(old);
    }

    final plugin = DshPlugin(
      id: manifest.pluginId,
      packageName: manifest.packageName,
      version: manifest.version,
      dirPath: dir.path,
      entryFile: manifest.entryFile,
      enabled: true,
      tools: tools,
    );
    plugins.add(plugin);
    await _persist();
    return plugin;
  }

  /// 解压归档（自动剥掉 GitHub 归档的顶层目录 `repo-main/`）
  Future<Directory> _extractArchive(Archive archive) async {
    final target = await _newPluginDir('plugin');
    String? commonPrefix;
    for (final file in archive) {
      if (file.isFile) {
        final name = file.name;
        if (commonPrefix == null) {
          final slash = name.indexOf('/');
          commonPrefix = slash > 0 ? name.substring(0, slash + 1) : '';
        } else if (commonPrefix.isNotEmpty && !name.startsWith(commonPrefix)) {
          commonPrefix = '';
        }
      }
    }
    for (final file in archive) {
      if (!file.isFile) continue;
      var rel = file.name;
      if (commonPrefix != null && commonPrefix.isNotEmpty &&
          rel.startsWith(commonPrefix)) {
        rel = rel.substring(commonPrefix.length);
      }
      if (rel.isEmpty) continue;
      final outPath = '${target.path}${Platform.pathSeparator}'
          '${rel.replaceAll('/', Platform.pathSeparator)}';
      // 防路径穿越
      if (!outPath.startsWith(target.path)) continue;
      final outFile = File(outPath);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(file.content as List<int>);
    }
    return target;
  }

  Future<Directory> _newPluginDir(String hint) async {
    await _ensureRootDir();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final dir = Directory('$_rootPath${Platform.pathSeparator}$hint-$stamp');    dir.createSync(recursive: true);
    return dir;
  }

  void _copyRecursive(Directory source, Directory target) {
    for (final entity in source.listSync(recursive: true)) {
      if (entity is! File) continue;
      final rel = entity.path.substring(source.path.length);
      final cleanRel = rel.startsWith(Platform.pathSeparator)
          ? rel.substring(1)
          : rel;
      final outPath = '${target.path}${Platform.pathSeparator}$cleanRel';
      if (!outPath.startsWith(target.path)) continue;
      File(outPath).parent.createSync(recursive: true);
      entity.copySync(outPath);
    }
  }

  // ---------- 管理 ----------

  Future<void> setEnabled(DshPlugin plugin, bool enabled) async {
    if (!enabled) {
      plugin.enabled = false;
      await _persist();
      plugins.refresh();
      return;
    }
    // 重新发现工具（插件可能已更新）
    try {
      final source = File(plugin.entryFile).readAsStringSync();
      plugin.tools = await DshRuntime.instance.discoverTools(source);
      plugin.enabled = true;
    } on DshPluginException {
      plugin.enabled = false;
      rethrow;
    }
    await _persist();
    plugins.refresh();
  }

  Future<void> remove(DshPlugin plugin) async {
    try {
      Directory(plugin.dirPath).deleteSync(recursive: true);
    } catch (_) {}
    plugins.remove(plugin);
    await _persist();
  }

  // ---------- 聊天层接口 ----------

  /// 全部启用插件的工具（聊天工具循环用）
  List<DshToolDef> get enabledTools => [
        for (final p in plugins)
          if (p.enabled) ...p.tools,
      ];

  /// 按工具名找到所属插件
  DshPlugin? pluginForTool(String toolName) {
    for (final p in plugins) {
      if (!p.enabled) continue;
      if (p.tools.any((t) => t.name == toolName)) return p;
    }
    return null;
  }

  Future<DshToolResult> callTool(
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    final plugin = pluginForTool(toolName);
    if (plugin == null) {
      return DshToolResult(ok: false, error: '插件工具不存在：$toolName');
    }
    final source = File(plugin.entryFile).readAsStringSync();
    return DshRuntime.instance.callTool(
      pluginSource: source,
      toolName: toolName,
      arguments: arguments,
    );
  }
}
