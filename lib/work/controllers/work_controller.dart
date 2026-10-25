import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/work_device.dart';
import '../models/work_permission.dart';
import '../services/work_registry.dart';

/// Work 工作台控制器：设备网格 + 本机被控档位设置
///
/// Phase 1：本地注册表增删 + 档位设置（网络发现与配对见后续阶段）
class WorkController extends GetxController {
  static const String _keyDeviceName = 'work_device_name';
  static const String _keyLocalTier = 'work_local_tier';

  final RxList<WorkDevice> devices = <WorkDevice>[].obs;

  /// 本机在被控端的档位 ID（对方请求时以此为准）
  final RxString localTierId = 'view_only'.obs;

  /// 本机设备名（对方设备列表里显示）
  final RxString deviceName = ''.obs;

  WorkPlatform get localPlatform => WorkPlatform.current;

  @override
  void onInit() {
    super.onInit();
    _loadLocal();
    refreshDevices();
  }

  Future<void> _loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    deviceName.value = prefs.getString(_keyDeviceName) ??
        '${localPlatform.label}-${DateTime.now().millisecondsSinceEpoch % 100000}';
    localTierId.value = prefs.getString(_keyLocalTier) ?? 'view_only';
  }

  Future<void> refreshDevices() async {
    devices.assignAll(await WorkRegistry.instance.listDevices());
  }

  /// 本机被控档位可选集合（桌面 3 档 / 移动 5 档）
  List<WorkPermissionTier> get localTiers =>
      WorkPermissions.tiersFor(localPlatform);

  WorkPermissionTier? get localTier => WorkPermissions.tierById(localTierId.value);

  /// 切换本机被控档位
  Future<void> setLocalTier(String tierId) async {
    localTierId.value = tierId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLocalTier, tierId);
  }

  Future<void> renameDevice(String name) async {
    deviceName.value = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDeviceName, name);
  }

  /// 添加设备（手动指定端点；配对令牌由 Phase 2 的握手产生，
  /// 这里先以 endpoint 派生占位令牌保证模型完整）
  Future<WorkDevice> addDevice({
    required String name,
    required String endpoint,
    required WorkPlatform platform,
    String tierId = 'view_only',
  }) async {
    final existing = await WorkRegistry.instance.findByEndpoint(endpoint);
    final device = WorkDevice(
      id: existing?.id ??
          'dev-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}',
      name: name,
      platform: platform,
      endpoint: endpoint,
      token: existing?.token ?? '',
      tierId: tierId,
      status: WorkDeviceStatus.pairing,
      createdAt: existing?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
      lastSeenAt: existing?.lastSeenAt,
      deviceModel: existing?.deviceModel,
    );
    await WorkRegistry.instance.upsert(device);
    await refreshDevices();
    return device;
  }

  Future<void> removeDevice(String id) async {
    await WorkRegistry.instance.remove(id);
    await refreshDevices();
  }

  /// 申请提高对端档位（控制端意图；实际生效以对端用户批准为准）
  Future<void> requestTier(String deviceId, String tierId) async {
    final idx = devices.indexWhere((d) => d.id == deviceId);
    if (idx < 0) return;
    final updated = devices[idx].copyWith(tierId: tierId);
    await WorkRegistry.instance.upsert(updated);
    devices[idx] = updated;
  }

  /// 配对成功后持久化对端令牌
  Future<void> updateDeviceToken(String deviceId, String token) async {
    final idx = devices.indexWhere((d) => d.id == deviceId);
    if (idx < 0) return;
    final updated = devices[idx].copyWith(
      token: token,
      status: WorkDeviceStatus.online,
      lastSeenAt: DateTime.now().millisecondsSinceEpoch,
    );
    await WorkRegistry.instance.upsert(updated);
    devices[idx] = updated;
  }
}
