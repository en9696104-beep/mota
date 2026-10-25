/// 任务页 —— 控制端对单台设备的调度界面
///
/// 三段式：指令规划（LLM 拆解 + 手动编辑）→ 执行进度（SSE 事件驱动）→
/// 人工审批（对应 Octop HITL 的 ask/allow_all/allow_actions 三态交互）。
library;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../theme/app_theme.dart';
import '../../services/api_service.dart';
import '../controllers/work_task_controller.dart';
import '../models/work_device.dart';
import '../models/work_permission.dart';
import '../models/work_task.dart';
import '../services/work_client.dart';
import '../services/work_guard.dart';
import '../services/work_planner.dart';

/// 对一台设备发起调度
class WorkTaskPage extends StatefulWidget {
  const WorkTaskPage({super.key, required this.device});

  final WorkDevice device;

  @override
  State<WorkTaskPage> createState() => _WorkTaskPageState();
}

class _WorkTaskPageState extends State<WorkTaskPage> {
  late final WorkTaskController _controller;

  @override
  void initState() {
    super.initState();
    // 按设备 tag 注册/复用控制器：重复进入不丢进行中的任务会话
    // （SSE 订阅与事件历史随控制器存活，服务端 history 重放兜底）
    final tag = widget.device.id;
    if (Get.isRegistered<WorkTaskController>(tag: tag)) {
      _controller = Get.find<WorkTaskController>(tag: tag);
    } else {
      _controller = Get.put<WorkTaskController>(
        WorkTaskController(widget.device),
        tag: tag,
      );
    }
    // 进入页面即探测对端权威状态（档位/平台/在线）
    _controller.probePeer();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.device.name,
            style: const TextStyle(fontSize: 16)),
        actions: <Widget>[
          Obx(() {
            final status = controller.peerStatus.value;
            final tier = status != null && status.ok
                ? WorkPermissions.tierById(status.tierId)
                : widget.device.tier;
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                    '对端：${tier?.label ?? '未知'}',
                    style: TextStyle(
                      color: tier?.requiresNativeGrant == true
                          ? AppColors.danger
                          : AppColors.accent,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
      body: Obx(() {
        final children = <Widget>[];
        // 被控端点未运行提示（对端需在设置中开启本地 API 服务）
        if (!ApiService.instance.isRunning.value && widget.device.endpoint.isNotEmpty) {
          // 仅提示：真正能否连上以 probePeer 结果为准
        }
        if (controller.hasActiveTask) {
          children.add(_ProgressCard(controller: controller));
        } else {
          children.add(_PlanCard(controller: controller, device: widget.device));
        }
        if (controller.taskError.value.isNotEmpty) {
          children.add(_ErrorBanner(text: controller.taskError.value));
        }
        if (controller.events.isNotEmpty) {
          children.add(_EventLog(events: controller.events.toList()));
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: <Widget>[
            ...children.map((w) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: w,
                )),
          ],
        );
      }),
    );
  }
}

// ---------------------------------------------------------------- 规划卡片

class _PlanCard extends StatefulWidget {
  const _PlanCard({required this.controller, required this.device});

  final WorkTaskController controller;
  final WorkDevice device;

  @override
  State<_PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends State<_PlanCard> {
  /// 指令输入框：跨重建保持（Obx 频繁刷新，不能内联创建）
  late final TextEditingController _instructionCtrl =
      TextEditingController(text: widget.controller.instruction.value);

  @override
  void dispose() {
    _instructionCtrl.dispose();
    super.dispose();
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
          const Text('任务指令',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            WorkPlanner.modelReady
                ? '用自然语言描述任务，本地模型会拆解为步骤'
                : '本地模型未加载：可手动添加步骤后直接下发',
            style: const TextStyle(
                color: AppColors.textTertiary, fontSize: 11, height: 1.5),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _instructionCtrl,
            minLines: 2,
            maxLines: 4,
            style: const TextStyle(
                color: AppColors.textPrimary, fontSize: 14, height: 1.5),
            onChanged: (v) => controller.instruction.value = v,
            decoration: InputDecoration(
              hintText: '如：看一下磁盘占用，再把 ~/notes/todo.txt 读给我',
              hintStyle: const TextStyle(
                  color: AppColors.textTertiary, fontSize: 12),
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
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.background,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: controller.planning.value
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.background),
                        )
                      : const Icon(Icons.auto_awesome, size: 18),
                  label: Text(controller.planning.value ? '拆解中…' : '拆解步骤'),
                  onPressed: controller.planning.value
                      ? null
                      : controller.planWithLlm,
                ),
              ),
            ],
          ),
          if (controller.planError.value.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(controller.planError.value,
                style: const TextStyle(
                    color: AppColors.danger, fontSize: 12, height: 1.5)),
          ],
          const SizedBox(height: 16),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              const Text('执行步骤',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Text('${controller.plannedSteps.length} 步',
                  style: const TextStyle(
                      color: AppColors.textTertiary, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          if (controller.plannedSteps.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('还没有步骤：点「拆解步骤」或用下方手动添加',
                  style: TextStyle(
                      color: AppColors.textTertiary, fontSize: 12)),
            )
          else
            ...controller.plannedSteps.toList().asMap().entries.map(
                  (e) => _StepPreviewRow(
                    index: e.key,
                    step: e.value,
                    onDelete: () => controller.removeStep(e.key),
                  ),
                ),
          const SizedBox(height: 10),
          _ManualAddRow(
            platform: widget.device.platform,
            onAdd: (action, target) =>
                controller.addStep(action: action, target: target),
          ),
          const SizedBox(height: 16),
          const Text('审批策略',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Obx(() => Wrap(
                spacing: 8,
                children: <Widget>[
                  _PolicyChip(
                    label: GuardMode.ask.label,
                    selected: controller.policyMode.value == GuardMode.ask,
                    onTap: () => controller.policyMode.value = GuardMode.ask,
                  ),
                  _PolicyChip(
                    label: GuardMode.allowAll.label,
                    selected:
                        controller.policyMode.value == GuardMode.allowAll,
                    onTap: () =>
                        controller.policyMode.value = GuardMode.allowAll,
                  ),
                ],
              )),
          const SizedBox(height: 4),
          const Text(
            '「每次询问」下每个步骤都会弹审批；「全部放行」跳过普通步骤，'
            '危险动作（删除/提权/写系统路径）仍强制审批',
            style: TextStyle(
                color: AppColors.textTertiary, fontSize: 11, height: 1.5),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.background,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.send, size: 18),
              label: const Text('下发任务'),
              onPressed: controller.plannedSteps.isEmpty
                  ? null
                  : () async {
                      final ok = await controller.submit();
                      if (!ok && controller.taskError.value.isNotEmpty) {
                        Get.snackbar(
                          '下发失败',
                          controller.taskError.value,
                          backgroundColor: AppColors.surfaceHigh,
                          colorText: AppColors.textPrimary,
                        );
                      }
                    },
            ),
          ),
        ],
      ),
    );
  }
}

/// 步骤预览行（规划态）
class _StepPreviewRow extends StatelessWidget {
  const _StepPreviewRow(
      {required this.index, required this.step, required this.onDelete});

  final int index;
  final WorkTaskStep step;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('${index + 1}',
                style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  WorkPlanner.labelOf(step.action),
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
                if (step.target != null && step.target!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(step.target!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontFamily: 'monospace')),
                ],
                const SizedBox(height: 2),
                Text(step.reason,
                    style: const TextStyle(
                        color: AppColors.textTertiary, fontSize: 11)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close,
                size: 16, color: AppColors.textTertiary),
            onPressed: onDelete,
            tooltip: '移除步骤',
          ),
        ],
      ),
    );
  }
}

/// 手动添加步骤行
class _ManualAddRow extends StatefulWidget {
  const _ManualAddRow({required this.platform, required this.onAdd});

  final WorkPlatform platform;
  final void Function(String action, String? target) onAdd;

  @override
  State<_ManualAddRow> createState() => _ManualAddRowState();
}

class _ManualAddRowState extends State<_ManualAddRow> {
  late String _action;
  final _targetCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _action = WorkPlanner.actionsForPlatform(widget.platform).first;
  }

  @override
  void dispose() {
    _targetCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final actions = WorkPlanner.actionsForPlatform(widget.platform);
    return Row(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: actions.contains(_action) ? _action : actions.first,
              isDense: true,
              dropdownColor: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(8),
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
              items: actions
                  .map((a) => DropdownMenuItem<String>(
                        value: a,
                        child: Text(WorkPlanner.labelOf(a)),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _action = v);
              },
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _targetCtrl,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
            decoration: InputDecoration(
              isDense: true,
              hintText: '路径 / 命令 / 坐标（可空）',
              hintStyle: const TextStyle(
                  color: AppColors.textTertiary, fontSize: 12),
              filled: true,
              fillColor: AppColors.surfaceHigh,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.border),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          icon: const Icon(Icons.add_circle_outline,
              color: AppColors.accent, size: 22),
          tooltip: '添加步骤',
          onPressed: () {
            widget.onAdd(_action, _targetCtrl.text);
            _targetCtrl.clear();
          },
        ),
      ],
    );
  }
}

class _PolicyChip extends StatelessWidget {
  const _PolicyChip(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      selectedColor: AppColors.accentSoft,
      backgroundColor: AppColors.surfaceHigh,
      labelStyle: TextStyle(
        color: selected ? AppColors.accent : AppColors.textSecondary,
      ),
      side: const BorderSide(color: AppColors.border),
      onSelected: (_) => onTap(),
    );
  }
}

// ---------------------------------------------------------------- 进度卡片

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.controller});

  final WorkTaskController controller;

  @override
  Widget build(BuildContext context) {
    final status = controller.taskStatus.value;
    final approval = controller.approvalRequest.value;
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
              if (!status.isTerminal) ...<Widget>[
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.accent),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                status.label,
                style: TextStyle(
                  color: status == WorkTaskStatus.failed
                      ? AppColors.danger
                      : AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text('任务 ${controller.taskId.value}',
                  style: const TextStyle(
                      color: AppColors.textTertiary, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 12),
          ...controller.liveSteps.toList().asMap().entries.map(
                (e) => _LiveStepRow(index: e.key, step: e.value),
              ),
          if (approval != null) ...<Widget>[
            const SizedBox(height: 12),
            _ApprovalCard(controller: controller, request: approval),
          ],
        ],
      ),
    );
  }
}

class _LiveStepRow extends StatelessWidget {
  const _LiveStepRow({required this.index, required this.step});

  final int index;
  final WorkTaskStep step;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color) = switch (step.status) {
      WorkStepStatus.pending => (Icons.circle_outlined, AppColors.textTertiary),
      WorkStepStatus.running => (Icons.more_horiz, AppColors.accent),
      WorkStepStatus.done => (Icons.check_circle, AppColors.accent),
      WorkStepStatus.failed => (Icons.error_outline, AppColors.danger),
      WorkStepStatus.rejected => (Icons.block, AppColors.danger),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${index + 1}. ${WorkPlanner.labelOf(step.action)}'
                  '${step.target != null && step.target!.isNotEmpty ? ' · ${step.target}' : ''}',
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 13),
                ),
                if (step.result != null && step.result!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      step.result!,
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontFamily: 'monospace',
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
                if (step.error != null && step.error!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(step.error!,
                      style: const TextStyle(
                          color: AppColors.danger,
                          fontSize: 11,
                          height: 1.4)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 审批卡片（HITL 交互核心）
class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({required this.controller, required this.request});

  final WorkTaskController controller;
  final Map<String, dynamic> request;

  @override
  Widget build(BuildContext context) {
    final action = request['action'] as String? ?? '';
    final target = request['target'] as String?;
    final reason = request['reason'] as String?;
    final guardReason = request['guard_reason'] as String?;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(Icons.gpp_maybe_outlined,
                  size: 18, color: AppColors.accent),
              SizedBox(width: 8),
              Text('等待审批',
                  style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          Text('动作：${WorkPlanner.labelOf(action)}（$action）',
              style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 13)),
          if (target != null && target.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(target,
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontFamily: 'monospace')),
          ],
          if (reason != null && reason.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text('理由：$reason',
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.5)),
          ],
          if (guardReason != null && guardReason.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text('护栏：$guardReason',
                style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                    height: 1.5)),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.background,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                ),
                onPressed: () => controller.approve('allow'),
                child: const Text('允许'),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                ),
                onPressed: () =>
                    controller.approve('allow_action', action: action),
                child: const Text('放行此动作', style: TextStyle(fontSize: 12)),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                ),
                onPressed: () => controller.approve('allow_all'),
                child: const Text('本任务全部放行',
                    style: TextStyle(fontSize: 12)),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: BorderSide(
                      color: AppColors.danger.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                ),
                onPressed: () => controller.approve('deny'),
                child: const Text('拒绝'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- 辅助组件

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.error_outline,
              size: 16, color: AppColors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: AppColors.danger, fontSize: 12, height: 1.5)),
          ),
        ],
      ),
    );
  }
}

class _EventLog extends StatelessWidget {
  const _EventLog({required this.events});

  final List<WorkTaskEvent> events;

  @override
  Widget build(BuildContext context) {
    final recent = events.take(30).toList();
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Theme(
        data: Theme.of(context)
            .copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          iconColor: AppColors.textTertiary,
          collapsedIconColor: AppColors.textTertiary,
          title: Text('事件日志（${events.length}）',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
          children: recent
              .map((e) => Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceHigh,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(e.type,
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 10,
                                  fontFamily: 'monospace')),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _eventSummary(e),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppColors.textTertiary, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }

  static String _eventSummary(WorkTaskEvent e) {
    final p = e.payload;
    switch (e.type) {
      case 'step_done':
        return (p['output'] as String? ?? '').trim();
      case 'step_failed':
        return (p['reason'] as String? ?? '').trim();
      case 'approval_request':
        return '${p['action']} ${p['target'] ?? ''}'.trim();
      case 'task_failed':
        return (p['error'] as String? ?? '').trim();
      default:
        return '';
    }
  }
}
