import 'work_permission.dart';

/// 配对状态
enum WorkDeviceStatus {
  /// 已配对且最近一次探测在线
  online('online', '在线'),

  /// 已配对但探测失败（离线/休眠）
  offline('offline', '离线'),

  /// 已发起配对请求，等待对端确认
  pairing('pairing', '等待确认');

  const WorkDeviceStatus(this.id, this.label);

  final String id;
  final String label;
}

/// 一台已配对的 MOTA 设备（被控节点 / Worker）
class WorkDevice {
  const WorkDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.endpoint,
    required this.token,
    required this.tierId,
    required this.status,
    required this.createdAt,
    this.lastSeenAt,
    this.deviceModel,
    this.agentReady = false,
  });

  /// 稳定 ID（对端设备自产 UUID）
  final String id;

  /// 用户备注名（如「书房 PC」）
  final String name;

  final WorkPlatform platform;

  /// 对端 HTTP 端点（如 http://192.168.1.5:8080）
  final String endpoint;

  /// 配对令牌（Bearer，被控端校验）
  final String token;

  /// 对端当前生效的权限档位 ID
  final String tierId;

  final WorkDeviceStatus status;

  final int createdAt;

  /// 最近一次成功探测时间（epoch ms）
  final int? lastSeenAt;

  /// 对端设备型号（探测获得，如 'Redmi K60' / 'DESKTOP-ABC'）
  final String? deviceModel;

  /// 对端推理引擎是否就绪（可承担 Agent 大脑）
  final bool agentReady;

  WorkPermissionTier? get tier => WorkPermissions.tierById(tierId);

  /// 该设备能否执行给定动作（按对端申报档位判定）
  bool canDo(String action) {
    final t = tier;
    if (t == null) return false;
    return WorkCapabilities.allows(t, action);
  }

  WorkDevice copyWith({
    String? name,
    String? endpoint,
    String? token,
    String? tierId,
    WorkDeviceStatus? status,
    int? lastSeenAt,
    String? deviceModel,
    bool? agentReady,
  }) => WorkDevice(
    id: id,
    name: name ?? this.name,
    platform: platform,
    endpoint: endpoint ?? this.endpoint,
    token: token ?? this.token,
    tierId: tierId ?? this.tierId,
    status: status ?? this.status,
    createdAt: createdAt,
    lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    deviceModel: deviceModel ?? this.deviceModel,
    agentReady: agentReady ?? this.agentReady,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'platform': platform.id,
    'endpoint': endpoint,
    'token': token,
    'tier_id': tierId,
    'created_at': createdAt,
    'last_seen_at': lastSeenAt,
    'device_model': deviceModel,
    'agent_ready': agentReady,
  };

  static WorkDevice fromJson(Map<String, dynamic> json) => WorkDevice(
    id: json['id'] as String,
    name: json['name'] as String? ?? '未命名设备',
    platform: WorkPlatform.fromId(json['platform'] as String?),
    endpoint: json['endpoint'] as String,
    token: json['token'] as String? ?? '',
    tierId: json['tier_id'] as String? ?? 'view_only',
    status: WorkDeviceStatus.offline,
    createdAt: json['created_at'] as int? ?? 0,
    lastSeenAt: json['last_seen_at'] as int?,
    deviceModel: json['device_model'] as String?,
    agentReady: json['agent_ready'] as bool? ?? false,
  );
}
