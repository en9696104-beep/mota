import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../controllers/work_controller.dart';
import '../models/work_device.dart';
import '../models/work_permission.dart';
import '../screens/work_task_page.dart';
import '../services/work_agent_server.dart';

/// Work 工作台 —— 第四个底部 Tab
///
/// 跨设备 Agent 调度入口：设备网格（已配对 MOTA 设备）+ 本机被控档位。
/// 设计借鉴 Octop（MIT）的权限分层思想，UI 为 MOTA 原生重写。
class WorkPage extends StatelessWidget {
  const WorkPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(WorkController());
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('工作台'.tr),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.add_link),
            tooltip: '添加设备'.tr,
            onPressed: () => _showAddDeviceSheet(context, controller),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.accent,
        backgroundColor: AppColors.surface,
        onRefresh: controller.refreshDevices,
        child: Obx(() {
          final list = controller.devices.toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: <Widget>[
              _SectionHeader(title: '本机节点'.tr, count: null),
              _LocalAgentCard(controller: controller),
              const SizedBox(height: 20),
              _SectionHeader(
                title: '我的设备'.tr,
                count: list.length,
                onAdd: () => _showAddDeviceSheet(context, controller),
              ),
              if (list.isEmpty)
                const _EmptyDevices()
              else
                ...list.map(
                  (d) => _DeviceCard(device: d, controller: controller),
                ),
            ],
          );
        }),
      ),
    );
  }
}

/// 本机信息卡：本机作为被控节点时的身份与档位
class _LocalAgentCard extends StatefulWidget {
  const _LocalAgentCard({required this.controller});

  final WorkController controller;

  @override
  State<_LocalAgentCard> createState() => _LocalAgentCardState();
}

class _LocalAgentCardState extends State<_LocalAgentCard> {
  String _pairCode = '······';

  @override
  void initState() {
    super.initState();
    _loadPairCode();
  }

  Future<void> _loadPairCode() async {
    final code = await WorkAgentServer.instance.ensurePairCode();
    if (mounted) setState(() => _pairCode = code);
  }

  Future<void> _refreshPairCode() async {
    final code = await WorkAgentServer.instance.regeneratePairCode();
    if (mounted) setState(() => _pairCode = code);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.dns_outlined,
                  color: AppColors.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Obx(
                      () => Text(
                        controller.deviceName.value,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '本机 · @p · 被控节点'.trParams({
                        'p': controller.localPlatform.label,
                      }),
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Text(
                '他人请求本机时的权限档位'.tr,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Obx(
                () => _TierDropdown(
                  tiers: controller.localTiers,
                  value: controller.localTierId.value,
                  onChanged: controller.setLocalTier,
                ),
              ),
            ],
          ),
          Obx(() {
            final tier = controller.localTier;
            if (tier == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    tier.requiresNativeGrant
                        ? Icons.warning_amber_outlined
                        : Icons.info_outline,
                    size: 14,
                    color: tier.requiresNativeGrant
                        ? AppColors.danger
                        : AppColors.textTertiary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      tier.requiresNativeGrant
                          ? '@t（授权引导见设备详情）'.trParams({
                              't': tier.nativeGrantLabel ?? '',
                            })
                          : tier.description,
                      style: TextStyle(
                        color: tier.requiresNativeGrant
                            ? AppColors.danger
                            : AppColors.textTertiary,
                        fontSize: 11,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 14),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 14),
          // 配对码：对端在 Work 工作台添加本设备时输入
          Row(
            children: <Widget>[
              Text(
                '本机配对码'.tr,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Text(
                _pairCode,
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 6,
                  fontFamily: 'monospace',
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.refresh,
                  size: 18,
                  color: AppColors.textTertiary,
                ),
                tooltip: '刷新配对码（旧码立即作废）'.tr,
                onPressed: _refreshPairCode,
              ),
            ],
          ),
          // 被控服务开关：本页直达，无需跳设置
          // （配对依赖局域网访问，开启时自动以 0.0.0.0 监听）
          Obx(() {
            final api = ApiService.instance;
            final running = api.isRunning.value;
            return Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.lan_outlined,
                    size: 18,
                    color: running ? AppColors.accent : AppColors.textTertiary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '被控服务（允许局域网访问）'.tr,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          running
                              ? '已开启 · ${api.bindAddress.value}:${api.port.value}'
                                    .tr
                              : '关闭状态下其他设备无法配对/调度本机'.tr,
                          style: TextStyle(
                            color: running
                                ? AppColors.accent
                                : AppColors.textTertiary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: running,
                    activeThumbColor: AppColors.accent,
                    onChanged: (v) async {
                      if (v) {
                        final ok = await api.start(allowLan: true);
                        if (!ok) {
                          Get.snackbar(
                            '启动失败'.tr,
                            '端口被占用或无网络权限，请稍后重试'.tr,
                            snackPosition: SnackPosition.BOTTOM,
                          );
                        }
                      } else {
                        await api.stop();
                      }
                    },
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 6),
          Obx(() {
            final running = ApiService.instance.isRunning.value;
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    running ? Icons.check_circle_outline : Icons.info_outline,
                    size: 14,
                    color: running ? AppColors.accent : AppColors.textTertiary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      running
                          ? '对方在 MOTA 工作台添加设备时，输入此配对码即可配对本机'.tr
                          : '开启被控服务后，对端输入上方配对码即可配对本机'.tr,
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.count, this.onAdd});

  final String title;
  final int? count;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (count != null) ...<Widget>[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ),
          ],
          const Spacer(),
          if (onAdd != null)
            GestureDetector(
              onTap: onAdd,
              child: Row(
                children: <Widget>[
                  const Icon(Icons.add, size: 16, color: AppColors.accent),
                  const SizedBox(width: 2),
                  Text(
                    '添加'.tr,
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyDevices extends StatelessWidget {
  const _EmptyDevices();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: <Widget>[
          const Icon(
            Icons.hub_outlined,
            color: AppColors.textTertiary,
            size: 36,
          ),
          const SizedBox(height: 12),
          Text(
            '还没有配对任何设备'.tr,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '在另一台设备的 MOTA 中开启工作台，\n输入其 IP 与端口即可发起配对'.tr,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 12,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device, required this.controller});

  final WorkDevice device;
  final WorkController controller;

  Color get _statusColor => device.status == WorkDeviceStatus.online
      ? AppColors.accent
      : AppColors.textTertiary;

  @override
  Widget build(BuildContext context) {
    final tier = device.tier;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              device.platform.isMobile
                  ? Icons.smartphone_outlined
                  : Icons.desktop_windows_outlined,
              color: AppColors.textSecondary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        device.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      device.status.label,
                      style: TextStyle(color: _statusColor, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${device.platform.label} · ${device.endpoint}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 档位徽章：点击弹出切换（控制端申请值）
          GestureDetector(
            onTap: () => _showTierSheet(context, controller),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: tier?.requiresNativeGrant == true
                    ? AppColors.danger.withValues(alpha: 0.12)
                    : AppColors.accentSoft,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: tier?.requiresNativeGrant == true
                      ? AppColors.danger.withValues(alpha: 0.4)
                      : AppColors.accent.withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                tier?.label ?? '未知档位'.tr,
                style: TextStyle(
                  color: tier?.requiresNativeGrant == true
                      ? AppColors.danger
                      : AppColors.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          // 发起调度（控制端任务页）
          IconButton(
            icon: const Icon(
              Icons.bolt_outlined,
              size: 20,
              color: AppColors.accent,
            ),
            tooltip: '发起调度'.tr,
            onPressed: () => Get.to(() => WorkTaskPage(device: device)),
          ),
          PopupMenuButton<String>(
            icon: const Icon(
              Icons.more_vert,
              size: 18,
              color: AppColors.textTertiary,
            ),
            color: AppColors.surfaceHigh,
            onSelected: (value) {
              if (value == 'delete') controller.removeDevice(device.id);
            },
            itemBuilder: (_) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'delete',
                child: Text(
                  '解绑设备'.tr,
                  style: const TextStyle(color: AppColors.danger, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showTierSheet(BuildContext context, WorkController controller) {
    final tiers = WorkPermissions.tiersFor(device.platform);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '申请对端权限档位'.tr,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ...tiers.map(
              (t) => ListTile(
                leading: Icon(
                  device.tierId == t.id
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: device.tierId == t.id
                      ? AppColors.accent
                      : AppColors.textTertiary,
                  size: 20,
                ),
                title: Text(
                  t.label,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  t.description,
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
                onTap: () {
                  controller.requestTier(device.id, t.id);
                  Navigator.pop(context);
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// 档位下拉（本机被控档位选择用）
class _TierDropdown extends StatelessWidget {
  const _TierDropdown({
    required this.tiers,
    required this.value,
    required this.onChanged,
  });

  final List<WorkPermissionTier> tiers;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: tiers.any((t) => t.id == value) ? value : tiers.first.id,
          isDense: true,
          dropdownColor: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(10),
          style: const TextStyle(color: AppColors.accent, fontSize: 13),
          items: tiers
              .map(
                (t) => DropdownMenuItem<String>(
                  value: t.id,
                  child: Text(
                    t.label,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

/// 添加设备面板：手动输入端点发起配对
void _showAddDeviceSheet(BuildContext context, WorkController controller) {
  final nameCtrl = TextEditingController();
  final endpointCtrl = TextEditingController(text: 'http://');
  final platform = WorkPlatform.linux.obs;

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '添加设备'.tr,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '输入对端 MOTA 的地址（对端需开启局域网访问）'.tr,
            style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
          ),
          const SizedBox(height: 16),
          _SheetField(
            controller: nameCtrl,
            label: '备注名'.tr,
            hint: '如：书房 PC'.tr,
          ),
          const SizedBox(height: 12),
          _SheetField(
            controller: endpointCtrl,
            label: '端点地址'.tr,
            hint: 'http://192.168.1.5:8080',
          ),
          const SizedBox(height: 12),
          Obx(
            () => Row(
              children: <Widget>[
                Text(
                  '平台'.tr,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 12),
                ...WorkPlatform.values
                    .where((p) => p != WorkPlatform.unknown)
                    .map(
                      (p) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(
                            p.label,
                            style: const TextStyle(fontSize: 12),
                          ),
                          selected: platform.value == p,
                          selectedColor: AppColors.accentSoft,
                          backgroundColor: AppColors.surfaceHigh,
                          labelStyle: TextStyle(
                            color: platform.value == p
                                ? AppColors.accent
                                : AppColors.textSecondary,
                          ),
                          side: const BorderSide(color: AppColors.border),
                          onSelected: (_) => platform.value = p,
                        ),
                      ),
                    ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () async {
                final name = nameCtrl.text.trim();
                var endpoint = endpointCtrl.text.trim();
                if (name.isEmpty || endpoint.isEmpty) return;
                if (!endpoint.startsWith('http')) {
                  endpoint = 'http://$endpoint';
                }
                await controller.addDevice(
                  name: name,
                  endpoint: endpoint,
                  platform: platform.value,
                );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text('发起配对'.tr),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SheetField extends StatelessWidget {
  const _SheetField({
    required this.controller,
    required this.label,
    required this.hint,
  });

  final TextEditingController controller;
  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
        ),
        hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
        filled: true,
        fillColor: AppColors.surfaceHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
      ),
    );
  }
}
