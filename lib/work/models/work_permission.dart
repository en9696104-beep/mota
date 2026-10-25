/// 权限档位体系 —— Work 工作台跨设备 Agent 调度的安全基座
///
/// 设计借鉴 [Octop](https://github.com/TencentCloud/Octop)（MIT License,
/// Copyright (c) 2026 Octop）的权限分层与工具审批思想，按 MOTA 设备网格
/// 形态重写：每台 MOTA 设备既是潜在被控节点（Worker）也是控制端。
///
/// 档位分平台：
/// - 桌面端（Win / macOS / Linux）3 档：仅查看 / 仅修改指定文件 / 完全权限
/// - 移动端（Android / iOS）5 档：仅查看 / 仅修改指定文件 / 无障碍 / Shizuku / Root
///
/// 每个档位声明能力位（[WorkCapability]），执行器按能力位过滤动作，
/// 未授权动作一律拒绝并回传原因（不做静默降级）。
library;

import 'dart:io' show Platform;

/// 平台无关的能力位。动作 → 能力位的映射见 [WorkCapabilities.ofAction]
enum WorkCapability {
  /// 列举/读取文件（含应用自有目录）
  readFiles,

  /// 写入/修改文件（restricted 档仅限白名单目录，full 档为全量）
  writeFiles,

  /// 执行 shell / 进程命令
  executeShell,

  /// UI 自动化（点击/滑动/读取屏幕，无障碍档起）
  controlUi,

  /// 系统级特权（root/su、系统设置等）
  systemPrivileged,

  /// 设备状态探测（型号/内存/存储/屏幕参数）
  deviceInfo,
}

/// 单个权限档位
class WorkPermissionTier {
  const WorkPermissionTier({
    required this.id,
    required this.label,
    required this.description,
    required this.capabilities,
    this.requiresNativeGrant = false,
    this.nativeGrantLabel,
  });

  /// 稳定 ID（持久化与协议传输用），如 'view_only'
  final String id;

  /// 展示名，如 '仅查看'
  final String label;

  /// 一句话说明该档位能做什么、不能做什么
  final String description;

  /// 该档位授予的能力位集合
  final Set<WorkCapability> capabilities;

  /// 是否需要 Android 系统级授权（无障碍 / Shizuku / Root）
  final bool requiresNativeGrant;

  /// 需要授权时的引导文案（如「请在系统设置开启无障碍服务」）
  final String? nativeGrantLabel;

  bool has(WorkCapability c) => capabilities.contains(c);
}

/// 设备平台
enum WorkPlatform {
  windows('windows', 'Windows', '桌面'),
  macos('macos', 'macOS', '桌面'),
  linux('linux', 'Linux', '桌面'),
  android('android', 'Android', '移动'),
  ios('ios', 'iOS', '移动'),
  unknown('unknown', '未知设备', '未知');

  const WorkPlatform(this.id, this.label, this.group);

  final String id;
  final String label;

  /// '桌面' 或 '移动'（决定档位集合）
  final String group;

  bool get isDesktop => group == '桌面';

  bool get isMobile => group == '移动';

  static WorkPlatform fromId(String? id) => WorkPlatform.values.firstWhere(
        (p) => p.id == id,
        orElse: () => WorkPlatform.unknown,
      );

  /// 当前运行平台（按 dart:io 解析；解析失败回落 unknown）
  static WorkPlatform get current {
    if (Platform.isWindows) return WorkPlatform.windows;
    if (Platform.isMacOS) return WorkPlatform.macos;
    if (Platform.isLinux) return WorkPlatform.linux;
    if (Platform.isAndroid) return WorkPlatform.android;
    if (Platform.isIOS) return WorkPlatform.ios;
    return WorkPlatform.unknown;
  }
}

/// 档位目录与能力矩阵
abstract final class WorkPermissions {
  /// 桌面端 3 档（递进）
  static const List<WorkPermissionTier> desktopTiers = <WorkPermissionTier>[
    WorkPermissionTier(
      id: 'view_only',
      label: '仅查看',
      description: '只能浏览设备信息与白名单目录内容，不能修改任何文件',
      capabilities: {WorkCapability.readFiles, WorkCapability.deviceInfo},
    ),
    WorkPermissionTier(
      id: 'restricted_files',
      label: '仅修改指定文件',
      description: '在授权目录内读写文件，目录外只读；不能执行命令',
      capabilities: {
        WorkCapability.readFiles,
        WorkCapability.writeFiles,
        WorkCapability.deviceInfo,
      },
    ),
    WorkPermissionTier(
      id: 'full_access',
      label: '完全权限',
      description: '全盘读写 + 执行 shell 命令，等同于把设备交给对方',
      capabilities: {
        WorkCapability.readFiles,
        WorkCapability.writeFiles,
        WorkCapability.executeShell,
        WorkCapability.deviceInfo,
      },
    ),
  ];

  /// 移动端 5 档（递进，后三档需系统授权）
  static const List<WorkPermissionTier> mobileTiers = <WorkPermissionTier>[
    WorkPermissionTier(
      id: 'view_only',
      label: '仅查看',
      description: '只能浏览设备信息与应用目录内容',
      capabilities: {WorkCapability.readFiles, WorkCapability.deviceInfo},
    ),
    WorkPermissionTier(
      id: 'restricted_files',
      label: '仅修改指定文件',
      description: '在授权目录内读写文件（如 MOTA 下载目录）',
      capabilities: {
        WorkCapability.readFiles,
        WorkCapability.writeFiles,
        WorkCapability.deviceInfo,
      },
    ),
    WorkPermissionTier(
      id: 'accessibility',
      label: '无障碍权限',
      description: '可代操作屏幕：点击、滑动、输入、读取界面文字',
      capabilities: {
        WorkCapability.readFiles,
        WorkCapability.writeFiles,
        WorkCapability.controlUi,
        WorkCapability.deviceInfo,
      },
      requiresNativeGrant: true,
      nativeGrantLabel: '请在系统设置 → 无障碍中开启 MOTA 工作台服务',
    ),
    WorkPermissionTier(
      id: 'shizuku',
      label: 'Shizuku 权限',
      description: '经 Shizuku 获得 adb 级 shell 权限，可执行系统命令',
      capabilities: {
        WorkCapability.readFiles,
        WorkCapability.writeFiles,
        WorkCapability.controlUi,
        WorkCapability.executeShell,
        WorkCapability.deviceInfo,
      },
      requiresNativeGrant: true,
      nativeGrantLabel: '请先安装并运行 Shizuku，然后在 MOTA 中授权',
    ),
    WorkPermissionTier(
      id: 'root',
      label: 'Root 权限',
      description: '完全控制设备：任意文件、任意命令、系统级操作（需已 Root）',
      capabilities: {
        WorkCapability.readFiles,
        WorkCapability.writeFiles,
        WorkCapability.controlUi,
        WorkCapability.executeShell,
        WorkCapability.systemPrivileged,
        WorkCapability.deviceInfo,
      },
      requiresNativeGrant: true,
      nativeGrantLabel: '需要设备已获取 Root 授权',
    ),
  ];

  /// 取某平台的档位列表
  static List<WorkPermissionTier> tiersFor(WorkPlatform platform) =>
      platform.isMobile ? mobileTiers : desktopTiers;

  /// 按 ID 查找档位（跨平台查找，协议对端用）
  static WorkPermissionTier? tierById(String? id) {
    if (id == null) return null;
    for (final t in <WorkPermissionTier>[...desktopTiers, ...mobileTiers]) {
      if (t.id == id) return t;
    }
    return null;
  }
}

/// 动作 → 所需能力位。执行器与护栏共用此映射，保证「判定」与「执行」一致
abstract final class WorkCapabilities {
  static const Map<String, WorkCapability> _byAction = <String, WorkCapability>{
    'list_files': WorkCapability.readFiles,
    'read_file': WorkCapability.readFiles,
    'write_file': WorkCapability.writeFiles,
    'delete_file': WorkCapability.writeFiles,
    'run_shell': WorkCapability.executeShell,
    'tap': WorkCapability.controlUi,
    'swipe': WorkCapability.controlUi,
    'input_text': WorkCapability.controlUi,
    'read_screen': WorkCapability.controlUi,
    'device_info': WorkCapability.deviceInfo,
  };

  /// 动作所需能力位；未登记的动作一律按最高权限处理（拒绝）
  static WorkCapability? ofAction(String action) => _byAction[action];

  /// 已登记动作全集（UI 下拉与规划 prompt 共用，顺序即展示顺序）
  static List<String> get registeredActions => _byAction.keys.toList();

  /// 该档位能否执行该动作
  static bool allows(WorkPermissionTier tier, String action) {
    final cap = _byAction[action];
    if (cap == null) return false; // 未登记动作：默认拒绝
    return tier.has(cap);
  }
}
