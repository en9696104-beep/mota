/// LLM 任务拆解器 —— 自然语言指令 → 可执行步骤序列
///
/// 控制端用本地模型（LlamaService）把用户指令拆解为对端设备可执行的
/// 动作序列。设计要点：
/// - **prompt 由能力表动态生成**：动作清单直接取自 [WorkCapabilities]，
///   新增动作无需改 prompt；模型只能产出已登记动作（护栏还有第二道防线）
/// - **低温度**（0.2）：规划要确定性，不要创意
/// - **健壮解析**：容忍 markdown 代码围栏、前后杂质、字段缺失；
///   解析失败返回 null，由 UI 提示手动编辑
library;

import 'dart:convert';

import '../../services/llama_service.dart';
import '../models/work_permission.dart';
import '../models/work_task.dart';

/// 拆解结果
class PlanResult {
  const PlanResult(this.steps, {this.raw});

  /// 拆解出的步骤（已过滤未登记动作；可能为空列表）
  final List<WorkTaskStep> steps;

  /// 模型原始输出（调试/展示用）
  final String? raw;

  bool get isEmpty => steps.isEmpty;
}

class WorkPlanner {
  const WorkPlanner();

  /// 本地模型是否就绪（未就绪时 UI 应引导加载模型或手动编辑步骤）
  static bool get modelReady => LlamaService.instance.isLoaded;

  /// 用本地模型拆解指令。模型未加载或解析失败返回 null。
  Future<PlanResult?> plan(
    String instruction, {
    double temperature = 0.2,
    int maxTokens = 768,
  }) async {
    if (instruction.trim().isEmpty) return null;
    if (!modelReady) return null;
    final buffer = StringBuffer();
    try {
      await for (final chunk in LlamaService.instance.generateChatStream(
        <LlamaTurn>[
          LlamaTurn(role: 'system', content: systemPrompt),
          LlamaTurn(role: 'user', content: instruction.trim()),
        ],
        temperature: temperature,
        maxTokens: maxTokens,
      )) {
        buffer.write(chunk);
      }
    } catch (_) {
      return null;
    }
    final steps = parseSteps(buffer.toString());
    if (steps == null) return null;
    return PlanResult(steps, raw: buffer.toString());
  }

  /// 从模型输出提取步骤数组。
  ///
  /// 容忍：markdown 代码围栏、JSON 前后的解释文字、多余字段、缺 target。
  /// 过滤未登记动作（护栏会二次拒绝，但规划阶段就剔除体验更好）。
  /// 完全无法解析时返回 null。
  static List<WorkTaskStep>? parseSteps(String raw) {
    if (raw.trim().isEmpty) return null;
    var text = raw.trim();
    // 去掉 markdown 代码围栏
    text = text.replaceAll(RegExp(r'```(?:json)?', caseSensitive: false), '');
    // 截取第一个 '[' 到最后一个 ']' 之间的内容
    final start = text.indexOf('[');
    final end = text.lastIndexOf(']');
    if (start < 0 || end <= start) return null;
    final jsonText = text.substring(start, end + 1);
    Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } catch (_) {
      return null;
    }
    if (decoded is! List) return null;
    final steps = <WorkTaskStep>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final action = (item['action'] as String? ?? '').trim();
      if (action.isEmpty) continue;
      // 只保留已登记动作：未登记动作护栏必拒，提前剔除避免误导用户
      if (WorkCapabilities.ofAction(action) == null) continue;
      final reason = (item['reason'] as String? ?? '').trim();
      final target = (item['target'] as String?)?.trim();
      final args = item['args'];
      steps.add(WorkTaskStep(
        action: action,
        reason: reason.isEmpty ? '模型规划步骤' : reason,
        target: (target == null || target.isEmpty) ? null : target,
        args: args is Map ? args.cast<String, dynamic>() : const <String, dynamic>{},
      ));
    }
    return steps;
  }

  /// 动作清单文本（供 prompt 与 UI 提示共用）
  static String get actionCatalogText {
    final lines = <String>[
      '- device_info: 获取设备信息（型号/系统版本/内存/存储）',
      '- list_files: 列举目录内容，target 为目录路径',
      '- read_file: 读取文件内容，target 为文件路径',
      '- write_file: 写入文件，target 为文件路径，args.content 为要写入的内容',
      '- delete_file: 删除文件，target 为文件路径',
      '- run_shell: 执行 shell 命令，target 为命令字符串',
      '- tap: 点击屏幕坐标，args 传 {"x": 像素x, "y": 像素y}（仅移动端）',
      '- swipe: 滑动屏幕，args 传 {"x1","y1","x2","y2"}（仅移动端）',
      '- input_text: 输入文本，args 传 {"text": "内容"}（仅移动端）',
      '- read_screen: 读取当前屏幕文字（仅移动端）',
    ];
    return lines.join('\n');
  }

  /// 动作中文名（UI 展示）
  static const Map<String, String> actionLabels = <String, String>{
    'device_info': '设备信息',
    'list_files': '列目录',
    'read_file': '读文件',
    'write_file': '写文件',
    'delete_file': '删文件',
    'run_shell': '执行命令',
    'tap': '点击',
    'swipe': '滑动',
    'input_text': '输入文本',
    'read_screen': '读屏',
  };

  /// 动作中文名（未登记动作回落原名）
  static String labelOf(String action) => actionLabels[action] ?? action;

  /// 某平台下可手动添加的动作（过滤跨平台无效动作）
  static List<String> actionsForPlatform(WorkPlatform platform) {
    const mobileOnly = <String>{'tap', 'swipe', 'input_text', 'read_screen'};
    return WorkCapabilities.registeredActions
        .where((a) => platform.isMobile || !mobileOnly.contains(a))
        .toList();
  }

  /// 规划用的系统提示词
  static String get systemPrompt => '''
你是 MOTA 工作台的任务规划器。把用户的自然语言指令拆解为对目标设备执行的步骤序列。

可用动作（只能使用以下动作，不得自造）：
$actionCatalogText

输出规则：
1. 只输出一个 JSON 数组，不要输出任何解释文字，不要使用 Markdown 代码围栏
2. 数组每个元素形如：{"action":"动作名","reason":"这一步的理由","target":"作用对象","args":{}}
3. 步骤尽量少而精，通常 1-4 步；能一步完成的不要拆成多步
4. 用户指令信息不足时，用合理默认值补全（如缺省路径用当前用户主目录），不要反问
5. 目标设备的权限档位可能无法执行某些动作，那是运行时的事，你只管按指令规划
6. 危险操作（删除、执行命令）也要如实规划，运行时有人工审批把关''';
}
