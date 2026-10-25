/// 任务与步骤模型 —— Agent 调度的执行单元
///
/// 任务由控制端自然语言指令发起，被控端（或本地调度器）拆解为步骤序列；
/// 每个步骤声明所需动作，执行前经护栏（WorkGuard）按对端权限档位判定。
library;

/// 任务状态机
enum WorkTaskStatus {
  /// 已创建，等待拆解
  pending('pending', '等待中'),

  /// LLM 正在拆解步骤
  planning('planning', '规划中'),

  /// 步骤执行中
  running('running', '执行中'),

  /// 某步骤触发人工审批，挂起等待
  awaitingApproval('awaiting_approval', '待审批'),

  completed('completed', '已完成'),
  failed('failed', '失败'),
  cancelled('cancelled', '已取消');

  const WorkTaskStatus(this.id, this.label);

  final String id;
  final String label;

  bool get isTerminal =>
      this == WorkTaskStatus.completed ||
      this == WorkTaskStatus.failed ||
      this == WorkTaskStatus.cancelled;
}

/// 步骤状态
enum WorkStepStatus {
  pending('pending', '等待'),
  running('running', '执行中'),
  done('done', '完成'),
  failed('failed', '失败'),
  rejected('rejected', '被拒绝');

  const WorkStepStatus(this.id, this.label);

  final String id;
  final String label;
}

/// 单个执行步骤
class WorkTaskStep {
  const WorkTaskStep({
    required this.action,
    required this.reason,
    this.target,
    this.args = const <String, dynamic>{},
    this.status = WorkStepStatus.pending,
    this.result,
    this.error,
  });

  /// 动作名（须登记在 WorkCapabilities，如 list_files / write_file / run_shell）
  final String action;

  /// LLM 给出的一步理由（展示用，也是审批时给人看的上下文）
  final String reason;

  /// 作用对象（文件路径 / 包名 / shell 命令等）
  final String? target;

  /// 动作参数（JSON 值）
  final Map<String, dynamic> args;

  final WorkStepStatus status;

  /// 执行结果文本
  final String? result;

  /// 失败或被拒原因
  final String? error;

  WorkTaskStep copyWith({
    WorkStepStatus? status,
    String? result,
    String? error,
  }) =>
      WorkTaskStep(
        action: action,
        reason: reason,
        target: target,
        args: args,
        status: status ?? this.status,        result: result ?? this.result,
        error: error ?? this.error,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'action': action,
        'reason': reason,
        'target': target,
        'args': args,
        'status': status.id,
        'result': result,
        'error': error,
      };

  static WorkTaskStep fromJson(Map<String, dynamic> json) => WorkTaskStep(
        action: json['action'] as String? ?? '',
        reason: json['reason'] as String? ?? '',
        target: json['target'] as String?,
        args: (json['args'] as Map<String, dynamic>?) ?? const {},
        status: WorkStepStatus.values.firstWhere(
          (s) => s.id == json['status'],
          orElse: () => WorkStepStatus.pending,
        ),
        result: json['result'] as String?,
        error: json['error'] as String?,
      );
}

/// 一个跨设备 Agent 任务
class WorkTask {
  const WorkTask({
    required this.id,
    required this.deviceId,
    required this.instruction,
    required this.steps,
    required this.status,
    required this.createdAt,
    this.originDeviceId,
    this.error,
    this.finishedAt,
  });

  final String id;

  /// 目标设备 ID（本地任务的 deviceId 为本机）
  final String deviceId;

  /// 发起任务的设备 ID（与 deviceId 相同则为本地发起）
  final String? originDeviceId;

  /// 自然语言指令原文
  final String instruction;

  final List<WorkTaskStep> steps;

  final WorkTaskStatus status;

  final int createdAt;

  final String? error;

  final int? finishedAt;

  int get doneCount => steps.where((s) => s.status == WorkStepStatus.done).length;

  /// 当前等待执行的步骤（首个未完成步骤）
  WorkTaskStep? get currentStep {
    for (final s in steps) {
      if (s.status == WorkStepStatus.pending ||
          s.status == WorkStepStatus.running) {
        return s;
      }
    }
    return null;
  }

  WorkTask copyWith({
    List<WorkTaskStep>? steps,
    WorkTaskStatus? status,
    String? error,
    int? finishedAt,
  }) =>
      WorkTask(
        id: id,
        deviceId: deviceId,
        instruction: instruction,
        steps: steps ?? this.steps,
        status: status ?? this.status,
        createdAt: createdAt,
        originDeviceId: originDeviceId,
        error: error ?? this.error,
        finishedAt: finishedAt ?? this.finishedAt,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'device_id': deviceId,
        'origin_device_id': originDeviceId,
        'instruction': instruction,
        'steps': steps.map((s) => s.toJson()).toList(),
        'status': status.id,
        'created_at': createdAt,
        'error': error,
        'finished_at': finishedAt,
      };

  static WorkTask fromJson(Map<String, dynamic> json) => WorkTask(
        id: json['id'] as String,
        deviceId: json['device_id'] as String? ?? '',
        originDeviceId: json['origin_device_id'] as String?,
        instruction: json['instruction'] as String? ?? '',
        steps: ((json['steps'] as List?) ?? const [])
            .map((e) => WorkTaskStep.fromJson(e as Map<String, dynamic>))
            .toList(),
        status: WorkTaskStatus.values.firstWhere(
          (s) => s.id == json['status'],
          orElse: () => WorkTaskStatus.pending,
        ),
        createdAt: json['created_at'] as int? ?? 0,
        error: json['error'] as String?,
        finishedAt: json['finished_at'] as int?,
      );
}
