/// 桌面端任务执行器 —— 按权限档位过滤动作，未授权一律拒绝并回传原因
///
/// 对应 Octop（MIT）「工具执行前过 guard」的思路：执行器不自行判断权限，
/// 只接受 GuardDecision 已放行的动作；档位不足的拒绝也由护栏统一给出。
library;

import 'dart:io';

import '../models/work_permission.dart';

/// 单个动作的执行结果
class ExecResult {
  const ExecResult(this.ok, this.output);

  final bool ok;
  final String output;
}

/// 桌面执行器：文件 IO + 进程命令
class DesktopWorkExecutor {
  const DesktopWorkExecutor();

  /// restricted_files 档位下的白名单根目录（应用支持目录 + 下载目录 + 用户主目录）
  /// 真实产品中应由被控端用户在 UI 中自选；这里取安全默认集。
  static List<String> restrictedRoots = <String>[];

  /// 路径是否落在 restricted 白名单内
  static bool _withinRestricted(String path) {
    if (restrictedRoots.isEmpty) return false;
    final normalized = File(path).absolute.path;
    return restrictedRoots.any((root) {
      final r = Directory(root).absolute.path;
      return normalized == r ||
          normalized.startsWith('$r${Platform.pathSeparator}');
    });
  }

  /// 执行一个已放行的动作。[tier] 用于 restricted 档的目录收敛校验。
  Future<ExecResult> execute(
    String action,
    WorkPermissionTier tier, {
    String? target,
    Map<String, dynamic> args = const <String, dynamic>{},
  }) async {
    // 双重防线：执行器侧再校验一次能力位（护栏之外的第二道闸）
    if (!WorkCapabilities.allows(tier, action)) {
      return ExecResult(false, '权限档位「${tier.label}」不包含该操作');
    }
    try {
      switch (action) {
        case 'device_info':
          return ExecResult(true, _deviceInfo());
        case 'list_files':
          return await _listFiles(target ?? '.');
        case 'read_file':
          return await _readFile(target!);
        case 'write_file':
          return await _writeFile(target!, args);
        case 'delete_file':
          return await _deleteFile(target!, tier);
        case 'run_shell':
          return await _runShell(target!);
        default:
          return ExecResult(false, '动作 "$action" 未登记');
      }
    } catch (e) {
      return ExecResult(false, '执行异常: $e');
    }
  }

  String _deviceInfo() {
    return 'platform=${Platform.operatingSystem} '
        'version=${Platform.operatingSystemVersion} '
        'cores=${Platform.numberOfProcessors}';
  }

  Future<ExecResult> _listFiles(String dirPath) async {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return ExecResult(false, '目录不存在: $dirPath');
    final entries = dir.listSync(followLinks: false).take(200).map((e) {
      final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
      final type = e is Directory ? 'dir' : 'file';
      final size = e is File ? e.lengthSync() : 0;
      return '$type\t$size\t$name';
    }).toList();
    return ExecResult(true, entries.join('\n'));
  }

  Future<ExecResult> _readFile(String path) async {
    final file = File(path);
    if (!file.existsSync()) return ExecResult(false, '文件不存在: $path');
    if (file.lengthSync() > 2 * 1024 * 1024) {
      return const ExecResult(false, '文件超过 2MB，拒绝读取');
    }
    return ExecResult(true, file.readAsStringSync());
  }

  Future<ExecResult> _writeFile(String path, Map<String, dynamic> args) async {
    final content = args['content'] as String? ?? '';
    final append = args['append'] == true;
    final file = File(path);
    if (append && file.existsSync()) {
      await file.writeAsString(content, mode: FileMode.append, flush: true);
    } else {
      await file.writeAsString(content, flush: true);
    }
    return ExecResult(true, '已写入 ${content.length} 字符 → $path');
  }

  Future<ExecResult> _deleteFile(String path, WorkPermissionTier tier) async {
    // 系统路径 + restricted 档：一律拒绝删除
    final sysPrefixes = <String>[
      '/etc',
      '/usr',
      '/bin',
      '/sbin',
      '/boot',
      '/sys',
      '/proc',
    ];
    final normalized = File(path).absolute.path;
    final isSystem =
        sysPrefixes.any((p) => normalized.startsWith(p)) ||
        (Platform.isWindows &&
            normalized.toLowerCase().startsWith('c:\\windows'));
    if (isSystem) return const ExecResult(false, '系统路径禁止删除');
    if (tier.id == 'restricted_files' && !_withinRestricted(path)) {
      return const ExecResult(false, '该路径不在授权目录内');
    }
    final file = File(path);
    if (file.existsSync()) {
      await file.delete();
      return ExecResult(true, '已删除 $path');
    }
    final dir = Directory(path);
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
      return ExecResult(true, '已删除目录 $path');
    }
    return ExecResult(false, '路径不存在: $path');
  }

  Future<ExecResult> _runShell(String command) async {
    final result = await Process.run(
      Platform.isWindows ? 'cmd' : '/bin/sh',
      Platform.isWindows ? <String>['/c', command] : <String>['-c', command],
    ).timeout(const Duration(seconds: 30));
    final out = '${result.stdout}${result.stderr}'.trim();
    return ExecResult(result.exitCode == 0, out.isEmpty ? '(无输出)' : out);
  }
}
