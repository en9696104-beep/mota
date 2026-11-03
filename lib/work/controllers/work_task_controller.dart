/// 任务会话控制器 —— 控制端的一次跨设备调度
///
/// 生命周期：输入指令 → LLM 拆解（或手动编辑）→ 配对检查 →
/// 下发任务（携带会话策略）→ SSE 事件驱动步骤状态 → 审批回传。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../theme/app_theme.dart';
import '../models/work_device.dart';
import '../models/work_task.dart';
import '../services/work_client.dart';
import '../services/work_guard.dart';
import '../services/work_planner.dart';
import 'work_controller.dart';

/// 任务会话的一次性 UI 状态机
class WorkTaskController extends GetxController {
  WorkTaskController(this.device);

  final WorkDevice device;

  final WorkClient _client = WorkClient('');

  /// 指令输入
  final RxString instruction = ''.obs;

  /// 拆解中
  final RxBool planning = false.obs;

  /// 规划/手动编辑的步骤预览
  final RxList<WorkTaskStep> plannedSteps = <WorkTaskStep>[].obs;

  /// 规划错误提示（模型未加载 / 解析失败等）
  final RxString planError = ''.obs;

  /// 会话审批策略（对应 Octop HITL 三态）
  final Rx<GuardMode> policyMode = GuardMode.ask.obs;

  /// 下发后的任务 ID（空串表示尚未下发）
  final RxString taskId = ''.obs;

  /// 任务状态
  final Rx<WorkTaskStatus> taskStatus = WorkTaskStatus.pending.obs;

  /// 步骤执行态（下标对应 plannedSteps/submittedSteps）
  final RxList<WorkTaskStep> liveSteps = <WorkTaskStep>[].obs;

  /// 事件日志（最新在前）
  final RxList<WorkTaskEvent> events = <WorkTaskEvent>[].obs;

  /// 当前待审批请求（null 表示无）
  final Rx<Map<String, dynamic>?> approvalRequest = Rx<Map<String, dynamic>?>(
    null,
  );

  /// 任务级错误（下发失败 / 连接失败等）
  final RxString taskError = ''.obs;

  /// 对端实际状态（权威档位/平台，来自 /work/status）
  final Rx<WorkPeerStatus?> peerStatus = Rx<WorkPeerStatus?>(null);

  StreamSubscription<WorkTaskEvent>? _eventSub;

  bool get hasActiveTask => taskId.value.isNotEmpty;

  bool get taskFinished => taskStatus.value.isTerminal;

  @override
  void onClose() {
    _eventSub?.cancel();
    _client.close();
    super.onClose();
  }

  // ---------------------------------------------------------------- 规划

  /// 调用本地 LLM 拆解指令
  Future<void> planWithLlm() async {
    final text = instruction.value.trim();
    if (text.isEmpty) return;
    planning.value = true;
    planError.value = '';
    try {
      final result = await const WorkPlanner().plan(text);
      if (result == null) {
        planError.value = WorkPlanner.modelReady
            ? '模型输出无法解析，请手动编辑步骤'
            : '本地模型未加载：请先在 MOTA 中打开一个模型，或手动添加步骤';
        return;
      }
      if (result.isEmpty) {
        planError.value = '模型未产出可用步骤，请手动添加';
        return;
      }
      plannedSteps.assignAll(result.steps);
      liveSteps.assignAll(result.steps);
    } finally {
      planning.value = false;
    }
  }

  /// 手动添加步骤（无模型时的降级路径）
  void addStep({required String action, String? target, String? reason}) {
    if (action.isEmpty) return;
    final step = WorkTaskStep(
      action: action,
      reason: (reason == null || reason.trim().isEmpty)
          ? '手动添加'
          : reason.trim(),
      target: (target == null || target.trim().isEmpty) ? null : target.trim(),
    );
    plannedSteps.add(step);
    liveSteps.add(step);
  }

  void removeStep(int index) {
    if (index < 0 || index >= plannedSteps.length) return;
    plannedSteps.removeAt(index);
    if (hasActiveTask) return;
    liveSteps.removeAt(index);
  }

  // ---------------------------------------------------------------- 下发

  /// 探测对端状态（权威档位）；未配对时静默失败
  Future<void> probePeer() async {
    _client.endpoint = device.endpoint;
    _client.token = device.token.isEmpty ? null : device.token;
    final status = await _client.status();
    if (status.ok) peerStatus.value = status;
  }

  /// 下发任务。返回是否成功发起。
  Future<bool> submit() async {
    if (plannedSteps.isEmpty) {
      taskError.value = '没有可执行的步骤';
      return false;
    }
    taskError.value = '';
    _client.endpoint = device.endpoint;

    // 配对检查：无令牌先向对端配对
    if (device.token.isEmpty) {
      final code = await _askPairCode();
      if (code == null) return false; // 用户取消
      _client.token = null;
      final ok = await _client.pair(
        pairCode: code,
        deviceId: device.id,
        deviceName: Get.find<WorkController>().deviceName.value,
      );
      if (!ok) {
        taskError.value = '配对失败：配对码错误或对端未在线';
        return false;
      }
      await Get.find<WorkController>().updateDeviceToken(
        device.id,
        _client.token ?? '',
      );
    } else {
      _client.token = device.token;
    }

    final task = await _client.submitTask(
      instruction: instruction.value.trim(),
      steps: plannedSteps.toList(),
      originDeviceId: Get.find<WorkController>().deviceName.value,
      policy: _policyForMode(policyMode.value),
    );
    if (task == null) {
      taskError.value = '任务下发失败：对端无响应或拒绝';
      return false;
    }
    taskId.value = task.id;
    taskStatus.value = WorkTaskStatus.running;
    liveSteps.assignAll(plannedSteps.toList());
    events.clear();
    approvalRequest.value = null;
    _subscribeEvents(task.id);
    return true;
  }

  WorkGuardPolicy _policyForMode(GuardMode mode) => switch (mode) {
    GuardMode.ask => const WorkGuardPolicy(),
    GuardMode.allowAll => const WorkGuardPolicy.allowAll(),
    GuardMode.allowActions => const WorkGuardPolicy.allowActions(<String>{}),
  };

  void _subscribeEvents(String id) {
    _eventSub?.cancel();
    _eventSub = _client
        .taskEvents(id)
        .listen(
          _onEvent,
          onError: (Object e) {
            taskError.value = '事件流中断：$e';
          },
        );
  }

  // ---------------------------------------------------------------- 事件

  void _onEvent(WorkTaskEvent event) {
    events.insert(0, event);
    final payload = event.payload;
    switch (event.type) {
      case 'task_started':
        taskStatus.value = WorkTaskStatus.running;
      case 'step_started':
        _patchStep(payload['index'] as int?, status: WorkStepStatus.running);
      case 'step_done':
        _patchStep(
          payload['index'] as int?,
          status: WorkStepStatus.done,
          result: payload['output'] as String?,
        );
      case 'step_failed':
        _patchStep(
          payload['index'] as int?,
          status: WorkStepStatus.failed,
          error: payload['reason'] as String?,
        );
      case 'step_rejected':
        _patchStep(
          payload['index'] as int?,
          status: WorkStepStatus.rejected,
          error: '用户拒绝',
        );
      case 'approval_request':
        approvalRequest.value = payload;
        taskStatus.value = WorkTaskStatus.awaitingApproval;
        _patchStep(payload['index'] as int?, status: WorkStepStatus.running);
      case 'task_done':
        approvalRequest.value = null;
        taskStatus.value = WorkTaskStatus.completed;
      case 'task_failed':
        approvalRequest.value = null;
        taskStatus.value = WorkTaskStatus.failed;
        taskError.value = payload['error'] as String? ?? '任务失败';
    }
  }

  void _patchStep(
    int? index, {
    required WorkStepStatus status,
    String? result,
    String? error,
  }) {
    if (index == null || index < 0 || index >= liveSteps.length) return;
    liveSteps[index] = liveSteps[index].copyWith(
      status: status,
      result: result,
      error: error,
    );
    liveSteps.refresh();
  }

  // ---------------------------------------------------------------- 审批

  /// 审批回传（allow / allow_all / allow_action / deny）
  Future<void> approve(String decision, {String? action}) async {
    final id = taskId.value;
    if (id.isEmpty) return;
    final ok = await _client.approve(id, decision: decision, action: action);
    if (ok) approvalRequest.value = null;
  }

  // ---------------------------------------------------------------- 工具

  /// 弹框索取对端配对码（对端 Work Tab 本机信息卡展示）
  Future<String?> _askPairCode() async {
    final ctx = Get.context;
    if (ctx == null) return null;
    return Get.dialog<String>(_PairCodeDialog(deviceName: device.name));
  }
}

/// 配对码输入对话框（控制端）
class _PairCodeDialog extends StatefulWidget {
  const _PairCodeDialog({required this.deviceName});

  final String deviceName;

  @override
  State<_PairCodeDialog> createState() => _PairCodeDialogState();
}

class _PairCodeDialogState extends State<_PairCodeDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(
        '与「${widget.deviceName}」配对',
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '请在对端设备的 MOTA → 工作台中查看本机配对码（6 位数字）并输入：'.tr,
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 12,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            maxLength: 6,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              letterSpacing: 8,
            ),
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              counterText: '',
              filled: true,
              fillColor: AppColors.surfaceHigh,
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.accent),
              ),
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            '取消',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text(
            '配对',
            style: TextStyle(color: AppColors.background),
          ),
        ),
      ],
    );
  }
}
