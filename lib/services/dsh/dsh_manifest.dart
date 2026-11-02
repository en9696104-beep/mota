import 'dart:convert';
import 'dart:io';

import 'dsh_models.dart';

/// DSH 插件清单解析。
///
/// 解析最小兼容集：
/// - `package.json`：`name` / `version` / `main` / `dsh.bundle.patch`
/// - 补丁层文件（默认 `cordis.patch.yml`）：`insert:` 列表中的 `id` / `name`
///
/// 不引入完整 YAML 依赖，只解析本场景需要的键值结构。
class DshManifestParser {
  DshManifestParser._();

  /// 解析插件目录，返回清单；缺文件或格式不符时抛 [DshPluginException]。
  static DshManifest parse(String pluginDir) {
    final dir = Directory(pluginDir);
    if (!dir.existsSync()) {
      throw const DshPluginException('插件目录不存在');
    }

    final pkgFile = File('${dir.path}${Platform.pathSeparator}package.json');
    if (!pkgFile.existsSync()) {
      throw const DshPluginException('未找到 package.json（不是有效的插件包）');
    }
    Map<String, dynamic> pkg;
    try {
      final decoded = jsonDecode(pkgFile.readAsStringSync());
      if (decoded is! Map<String, dynamic>) {
        throw const DshPluginException('package.json 格式错误');
      }
      pkg = decoded;
    } on DshPluginException {
      rethrow;
    } catch (_) {
      throw const DshPluginException('package.json 解析失败');
    }

    final packageName = pkg['name'] as String?;
    if (packageName == null || packageName.isEmpty) {
      throw const DshPluginException('package.json 缺少 name 字段');
    }

    // dsh.bundle.patch：缺失即视为非 DSH 插件包，明确拒绝
    // （与 DSH 官方行为一致：无该字段的包不会激活）
    final dshSection = (pkg['dsh'] as Map?)?.cast<String, dynamic>();
    final patchPath =
        (dshSection?['bundle'] as Map?)?['patch'] as String?;
    if (patchPath == null || patchPath.isEmpty) {
      throw const DshPluginException(
        'package.json 缺少 dsh.bundle.patch 声明（不是 DSH 插件包）',
      );
    }
    final patchFile = File(
      '${dir.path}${Platform.pathSeparator}${_normalize(patchPath)}',
    );
    if (!patchFile.existsSync()) {
      throw DshPluginException('补丁层文件不存在：$patchPath');
    }

    final entry = _parsePatch(patchFile.readAsStringSync(), packageName);
    final entryFile = _resolveEntry(dir.path, entry.name, pkg['main'] as String?);

    return DshManifest(
      packageName: packageName,
      version: pkg['version'] as String? ?? '0.0.0',
      pluginId: entry.id,
      entryFile: entryFile,
      entryModule: entry.name,
    );
  }

  /// 解析 cordis.patch.yml，取第一个 insert 条目的 id 与 name。
  ///
  /// 兼容的形态：
  /// ```yaml
  /// insert:
  ///   - id: hello
  ///     name: './index.js'
  /// ```
  /// 也容忍条目内出现其他键（config 等），以及 `- insert:` 包装。
  static ({String id, String name}) _parsePatch(String content, String fallbackId) {
    String? id;
    String? name;
    var inInsert = false;
    for (final rawLine in content.split('\n')) {
      final line = rawLine.replaceFirst(RegExp(r'#.*$'), '').trimRight();
      if (line.trim().isEmpty) continue;
      if (RegExp(r'^insert\s*:').hasMatch(line.trim())) {
        inInsert = true;
        continue;
      }
      // 顶层出现其他键：退出 insert 区
      if (!line.startsWith(' ') && !line.startsWith('-')) {
        if (inInsert && id != null && name != null) break;
        inInsert = false;
        continue;
      }
      if (!inInsert) continue;
      final idMatch = RegExp(r'^-\s+(?:insert:\s*)?id\s*:\s*(.+)$').firstMatch(line.trim());
      if (idMatch != null) {
        // 新条目开始：只有第一个条目生效
        if (id != null && name != null) break;
        id ??= _stripQuotes(idMatch.group(1)!.trim());
        continue;
      }
      final nameMatch =
          RegExp(r'^-\s+name\s*:\s*(.+)$').firstMatch(line.trim()) ??
              RegExp(r'^name\s*:\s*(.+)$').firstMatch(line.trim());
      if (nameMatch != null && id != null && name == null) {
        name = _stripQuotes(nameMatch.group(1)!.trim());
      }
    }
    if (id == null || name == null) {
      throw const DshPluginException('cordis.patch.yml 中未找到有效的 insert 条目（id + name）');
    }
    return (id: id, name: name);
  }

  static String _stripQuotes(String s) {
    final t = s.trim();
    if (t.length >= 2 &&
        ((t.startsWith("'") && t.endsWith("'")) ||
            (t.startsWith('"') && t.endsWith('"')))) {
      return t.substring(1, t.length - 1);
    }
    return t;
  }

  /// 解析入口模块：相对路径相对插件目录；裸说明符仅支持包自身名（回退 main / index.js）
  static String _resolveEntry(String pluginDir, String module, String? main) {
    final sep = Platform.pathSeparator;
    if (module.startsWith('./') || module.startsWith('../') || module.startsWith('/')) {
      var path = module.startsWith('/')
          ? '$pluginDir$module'
          : '$pluginDir$sep${_normalize(module)}';
      // 无扩展名时补 .js 或 /index.js
      final file = File(path);
      if (!file.existsSync() && !path.endsWith('.js')) {
        if (File('$path.js').existsSync()) {
          path = '$path.js';
        } else if (File('$path${sep}index.js').existsSync()) {
          path = '$path${sep}index.js';
        }
      }
      if (!File(path).existsSync()) {
        throw DshPluginException('入口文件不存在：$module');
      }
      return path;
    }
    // 裸说明符：仅支持指向包自身（如 name 与包名相同的入口）
    final mainFile = main ?? 'index.js';
    final path = '$pluginDir$sep${_normalize(mainFile)}';
    if (File(path).existsSync()) return path;
    final withJs = '$pluginDir$sep${_normalize('$mainFile.js')}';
    if (File(withJs).existsSync()) return withJs;
    final indexFile = '$pluginDir${sep}index.js';
    if (File(indexFile).existsSync()) return indexFile;
    throw DshPluginException('无法解析入口模块：$module（裸说明符仅支持包自身入口）');
  }

  static String _normalize(String p) => p.replaceAll('/', Platform.pathSeparator);
}

/// 解析结果
class DshManifest {
  const DshManifest({
    required this.packageName,
    required this.version,
    required this.pluginId,
    required this.entryFile,
    required this.entryModule,
  });

  final String packageName;
  final String version;
  final String pluginId;
  final String entryFile;
  final String entryModule;
}
