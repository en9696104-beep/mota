/// 护栏与三态审批 —— 权限判定的唯一入口
///
/// 设计借鉴 [Octop](https://github.com/TencentCloud/Octop)（MIT License,
/// Copyright (c) 2026 Octop）的 HITL 三态会话审批与 tool_guard 规则模型：
/// - 每任务一个会话级审批策略（ask / allow_all / allow_actions）
/// - 「询问用户」类动作永不被绕过（对应 Octop 的 ask_user_question）
/// - 危险动作匹配护栏规则时强制走人工审批，无视会话级 allow_all
library;

import '../models/work_permission.dart';

/// 会话级审批模式（每任务一份）
enum GuardMode {
  /// 每个动作都问（默认）
  ask('ask', '每次询问'),

  /// 本任务内全部放行（护栏规则匹配的动作除外）
  allowAll('allow_all', '本任务全部放行'),

  /// 仅放行登记过的动作
  allowActions('allow_actions', '仅放行指定动作');

  const GuardMode(this.id, this.label);

  final String id;
  final String label;
}

/// 护栏规则匹配结果的动作分级
enum GuardVerdict {
  /// 直接放行（权限够且无规则命中）
  allow,

  /// 需人工审批
  requireApproval,

  /// 拒绝执行
  deny,
}

/// 护栏规则：命中即按 verdict 处置
class WorkGuardRule {
  const WorkGuardRule({
    required this.id,
    required this.action,
    this.pattern,
    this.verdict = GuardVerdict.requireApproval,
    this.note,
  });

  /// 规则 ID（如 'shell_rm_rf'）
  final String id;

  /// 适用动作名（'*' 表示全部）
  final String action;

  /// 对 target 的正则（null 表示该动作全命中）
  final String? pattern;

  final GuardVerdict verdict;

  /// 命中时展示给用户的说明
  final String? note;

  /// target 是否命中本规则
  bool matches(String actionName, String? target) {
    if (action != '*' && action != actionName) return false;
    if (pattern == null) return true;
    if (target == null) return false;
    return RegExp(pattern!).hasMatch(target);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'action': action,
        'pattern': pattern,
        'verdict': verdict.name,
        'note': note,
      };

  static WorkGuardRule fromJson(Map<String, dynamic> json) => WorkGuardRule(
        id: json['id'] as String? ?? '',
        action: json['action'] as String? ?? '*',
        pattern: json['pattern'] as String?,
        verdict: GuardVerdict.values.firstWhere(
          (v) => v.name == json['verdict'],
          orElse: () => GuardVerdict.requireApproval,
        ),
        note: json['note'] as String?,
      );
}

/// 每任务的会话审批策略（HITL 三态，对应 Octop HitlSessionPolicy）
class WorkGuardPolicy {
  const WorkGuardPolicy({this.mode = GuardMode.ask, this.actions = const {}});

  const WorkGuardPolicy.allowAll()
      : mode = GuardMode.allowAll,
        actions = const {};

  const WorkGuardPolicy.allowActions(Set<String> names)
      : mode = GuardMode.allowActions,
        actions = names;

  final GuardMode mode;

  /// allow_actions 模式下放行的动作名集合
  final Set<String> actions;

  /// 会话级是否放行该动作（不考虑护栏规则）
  bool sessionAllows(String action) {
    if (action == 'ask_user') return false; // 询问类永不被绕过
    switch (mode) {
      case GuardMode.ask:
        return false;
      case GuardMode.allowAll:
        return true;
      case GuardMode.allowActions:
        return actions.contains(action);
    }
  }

  WorkGuardPolicy withAction(String name) {
    if (mode == GuardMode.allowAll) return this;
    return WorkGuardPolicy.allowActions(<String>{...actions, name});
  }

  WorkGuardPolicy withoutAction(String name) =>
      WorkGuardPolicy.allowActions(actions.where((a) => a != name).toSet());

  Map<String, dynamic> toJson() => <String, dynamic>{
        'mode': mode.id,
        'actions': actions.toList(),
      };

  static WorkGuardPolicy fromJson(Map<String, dynamic> json) {
    final mode = GuardMode.values.firstWhere(
      (m) => m.id == json['mode'],
      orElse: () => GuardMode.ask,
    );
    final names = (json['actions'] as List?)?.cast<String>().toSet() ?? const {};
    return WorkGuardPolicy(mode: mode, actions: names);
  }
}

/// 护栏判定结果
class GuardDecision {
  const GuardDecision(this.verdict, {this.reason, this.rule});

  final GuardVerdict verdict;
  final String? reason;
  final WorkGuardRule? rule;

  bool get isAllowed => verdict == GuardVerdict.allow;
}

/// 护栏评估器：权限档位 + 会话策略 + 规则表 三者的合成判定
class WorkGuard {
  WorkGuard({List<WorkGuardRule>? rules}) : rules = rules ?? defaultRules;

  /// 默认规则表（对应 Octop  bundled tool_guard rules 的最小集）
  static const List<WorkGuardRule> defaultRules = <WorkGuardRule>[
    WorkGuardRule(
      id: 'shell_rm_rf',
      action: 'run_shell',
      pattern: r'rm\s+(-[a-zA-Z]*[rf][a-zA-Z]*\s+)+',
      verdict: GuardVerdict.requireApproval,
      note: '递归删除命令，需人工确认',
    ),
    WorkGuardRule(
      id: 'shell_sudo',
      action: 'run_shell',
      pattern: r'(^|[;&|]\s*)(sudo|su)\s',
      verdict: GuardVerdict.requireApproval,
      note: '提权命令，需人工确认',
    ),
    WorkGuardRule(
      id: 'shell_dd',
      action: 'run_shell',
      pattern: r'(^|[;&|]\s*)dd\s',
      verdict: GuardVerdict.deny,
      note: 'dd 直接写块设备，禁止执行',
    ),
    WorkGuardRule(
      id: 'write_outside_home',
      action: 'write_file',
      pattern: r'^(/etc|/usr|/bin|/sbin|/boot|/sys|/proc|C:\\Windows|C:\\Program)',
      verdict: GuardVerdict.requireApproval,
      note: '写入系统关键路径，需人工确认',
    ),
    WorkGuardRule(
      id: 'unknown_action',
      action: '*',
      pattern: null,
      verdict: GuardVerdict.deny,
      note: '未登记动作，默认拒绝',
    ),
  ];

  final List<WorkGuardRule> rules;

  /// 综合判定一个动作是否放行
  ///
  /// 优先级：未登记动作 deny → 规则表（deny > requireApproval）→
  /// 权限档位不足 deny → 会话策略 allow 则 allow，否则 requireApproval。
  GuardDecision evaluate({
    required WorkPermissionTier tier,
    required String action,
    String? target,
    WorkGuardPolicy? policy,
  }) {
    // 1) 未登记动作：直接拒绝（与 Octop 白名单思路一致）
    if (WorkCapabilities.ofAction(action) == null) {
      return GuardDecision(
        GuardVerdict.deny,
        reason: '动作 "$action" 未登记，已拒绝',
        rule: rules.firstWhere(
          (r) => r.id == 'unknown_action',
          orElse: () => const WorkGuardRule(
            id: 'unknown_action',
            action: '*',
            verdict: GuardVerdict.deny,
          ),
        ),
      );
    }

    // 2) 规则表：deny 优先于 requireApproval
    WorkGuardRule? hitDeny;
    WorkGuardRule? hitApproval;
    for (final rule in rules) {
      if (rule.id == 'unknown_action') continue;
      if (!rule.matches(action, target)) continue;
      if (rule.verdict == GuardVerdict.deny) {
        hitDeny ??= rule;
      } else if (rule.verdict == GuardVerdict.requireApproval) {
        hitApproval ??= rule;
      }
    }
    if (hitDeny != null) {
      return GuardDecision(
        GuardVerdict.deny,
        reason: hitDeny.note ?? '命中禁止规则',
        rule: hitDeny,
      );
    }

    // 3) 权限档位不足：拒绝（对端没有这个能力）
    if (!WorkCapabilities.allows(tier, action)) {
      return GuardDecision(
        GuardVerdict.deny,
        reason: '当前权限档位「${tier.label}」不包含该操作',
      );
    }

    // 4) 护栏命中：强制审批（会话 allow_all 也不能跳过）
    if (hitApproval != null) {
      return GuardDecision(
        GuardVerdict.requireApproval,
        reason: hitApproval.note ?? '命中需审批规则',
        rule: hitApproval,
      );
    }

    // 5) 会话策略
    final p = policy ?? const WorkGuardPolicy();
    if (p.sessionAllows(action)) {
      return const GuardDecision(GuardVerdict.allow);
    }
    return const GuardDecision(
      GuardVerdict.requireApproval,
      reason: '默认每次询问',
    );
  }
}
