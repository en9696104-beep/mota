/// 被控端 Agent 服务 —— Work 工作台的设备侧 HTTP 端点
///
/// 挂载在现有 ApiService（shelf）的 Router 上，与 OpenAI/MCP 端点共存：
/// - POST /work/pair              配对：配对码 → 令牌
/// - GET  /work/status            设备状态与能力宣告（需令牌）
/// - POST /work/task              下发任务（需令牌）
/// - GET  /work/task/{id}/events  任务事件 SSE 流（需令牌）
/// - POST /work/task/{id}/approve 审批回传（需令牌）
///
/// 设计借鉴 Octop（MIT）的工具审批与护栏模型：每个步骤执行前过
/// [WorkGuard] 三态判定（allow / requireApproval / deny），
/// requireApproval 的步骤挂起等待控制端审批事件。
library;

import 'dart:async'
    show Completer, StreamController, StreamSubscription, Timer, unawaited;
import 'dart:convert';
import 'dart:math';

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart' as shelf_router;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/work_permission.dart';
import '../models/work_task.dart';
import 'work_executor_desktop.dart';
import 'work_executor_mobile.dart';
import 'work_guard.dart';

/// 单个被控任务的运行时状态
class _TaskRuntime {
  _TaskRuntime(this.task);

  final WorkTask task;

  /// 事件广播（SSE 消费者）
  final StreamController<Map<String, dynamic>> events =
      StreamController<Map<String, dynamic>>.broadcast();

  /// 事件历史（重放给晚到的订阅者，对应 SSE 断线重连语义）
  final List<Map<String, dynamic>> history = <Map<String, dynamic>>[];

  /// 待审批步骤索引（-1 表示无）
  int awaitingIndex = -1;

  /// 审批 Completer：approve 端点完成时 complete(true/false)
  Completer<bool>? approvalCompleter;

  /// 每任务会话审批策略（HITL 三态）
  WorkGuardPolicy policy = const WorkGuardPolicy();

  /// 任务是否已终止（完成/失败）
  bool finished = false;
}

/// 被控端 Agent 服务单例
class WorkAgentServer {
  WorkAgentServer._();

  static final WorkAgentServer instance = WorkAgentServer._();

  static const String _prefsPairCode = 'work_pair_code';
  static const String _prefsTier = 'work_local_tier';

  final WorkGuard guard = WorkGuard();

  /// 桌面执行器（文件 IO + 进程命令）
  final DesktopWorkExecutor executor = const DesktopWorkExecutor();

  /// 移动执行器（无障碍 / Shizuku / Root；文件类委托桌面实现）
  final MobileWorkExecutor mobileExecutor = const MobileWorkExecutor();

  /// 按本机平台分发执行器：移动端走原生通道，桌面端走 dart:io
  Future<ExecResult> _execute(
    String action,
    WorkPermissionTier tier, {
    String? target,
    Map<String, dynamic> args = const <String, dynamic>{},
  }) {
    if (WorkPlatform.current.isMobile) {
      return mobileExecutor.execute(action, tier, target: target, args: args);
    }
    return executor.execute(action, tier, target: target, args: args);
  }

  /// 已授权令牌 → 设备 ID（重启后需重新配对，安全默认）
  final Map<String, String> _tokens = <String, String>{};

  /// 当前配对码（6 位数字；UI 生成/刷新）
  String? _pairCode;

  final Map<String, _TaskRuntime> _tasks = <String, _TaskRuntime>{};

  final Random _random = Random.secure();

  /// 当前生效的被控档位 ID（本机用户在 Work Tab 设置）
  String _localTierId = 'view_only';

  WorkPlatform get localPlatform => WorkPlatform.current;

  // ---------------------------------------------------------------- 生命周期

  /// 从 SharedPreferences 恢复配对码与档位
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _pairCode = prefs.getString(_prefsPairCode);
    _localTierId = prefs.getString(_prefsTier) ?? 'view_only';
  }

  /// 生成（或复用）配对码。返回 6 位数字字符串。
  Future<String> ensurePairCode() async {
    final existing = _pairCode;
    if (existing != null && existing.isNotEmpty) return existing;
    return regeneratePairCode();
  }

  /// 强制刷新配对码（旧配对码立即作废）
  Future<String> regeneratePairCode() async {
    final code = List.generate(6, (_) => _random.nextInt(10)).join();
    _pairCode = code;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsPairCode, code);
    return code;
  }

  /// 本机被控档位（Work Tab 修改时同步调用）
  Future<void> setLocalTier(String tierId) async {
    _localTierId = tierId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsTier, tierId);
  }

  // ---------------------------------------------------------------- 路由挂载

  /// 把 /work/* 路由挂到 ApiService 的 Router
  void mount(shelf_router.Router router) {
    router
      ..post('/work/pair', _handlePair)
      ..get('/work/status', _handleStatus)
      ..post('/work/task', _handleTask)
      ..get('/work/task/<taskId>/events', _handleTaskEvents)
      ..post('/work/task/<taskId>/approve', _handleApprove);
  }

  // ---------------------------------------------------------------- 鉴权

  String? _tokenOf(shelf.Request request) {
    final header = request.headers['authorization'];
    if (header == null) return null;
    if (!header.startsWith('Bearer ')) return null;
    final token = header.substring(7).trim();
    return token.isEmpty ? null : token;
  }

  bool _authorized(shelf.Request request) =>
      _tokens.containsKey(_tokenOf(request) ?? '');

  // ---------------------------------------------------------------- 处理器

  /// POST /work/pair —— 配对码换令牌
  Future<shelf.Response> _handlePair(shelf.Request request) async {
    Map<String, dynamic> body;
    try {
      final raw = await request.readAsString();
      body =
          (raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw))
              as Map<String, dynamic>;
    } catch (_) {
      return _json(400, <String, dynamic>{
        'ok': false,
        'error': '请求体不是合法 JSON',
      });
    }
    final code = (body['pair_code'] as String? ?? '').trim();
    final current = await ensurePairCode();
    if (code != current) {
      return _json(403, <String, dynamic>{'ok': false, 'error': '配对码错误或已过期'});
    }
    final deviceId =
        (body['device_id'] as String?) ?? 'peer-${_random.nextInt(1 << 32)}';
    final token = base64Url.encode(
      List<int>.generate(24, (_) => _random.nextInt(256)),
    );
    _tokens[token] = deviceId;
    return _json(200, <String, dynamic>{
      'ok': true,
      'token': token,
      'tier_id': _localTierId,
      'device': _deviceInfoJson(),
    });
  }

  /// GET /work/status —— 状态与能力宣告
  Future<shelf.Response> _handleStatus(shelf.Request request) async {
    if (!_authorized(request)) return _unauthorized();
    final tier = WorkPermissions.tierById(_localTierId);
    return _json(200, <String, dynamic>{
      'ok': true,
      'device': _deviceInfoJson(),
      'tier': tier == null
          ? null
          : <String, dynamic>{
              'id': tier.id,
              'label': tier.label,
              'capabilities': tier.capabilities.map((c) => c.name).toList(),
              'requires_native_grant': tier.requiresNativeGrant,
            },
      'agent_ready': false, // Phase 3 起反映 LlamaService 状态
    });
  }

  /// POST /work/task —— 下发任务（控制端已拆解为步骤）
  Future<shelf.Response> _handleTask(shelf.Request request) async {
    if (!_authorized(request)) return _unauthorized();
    Map<String, dynamic> body;
    try {
      final raw = await request.readAsString();
      body =
          (raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw))
              as Map<String, dynamic>;
    } catch (_) {
      return _json(400, <String, dynamic>{
        'ok': false,
        'error': '请求体不是合法 JSON',
      });
    }
    final instruction = body['instruction'] as String? ?? '';
    final rawSteps = body['steps'];
    if (instruction.isEmpty && rawSteps is! List) {
      return _json(400, <String, dynamic>{
        'ok': false,
        'error': '缺少 instruction 或 steps',
      });
    }
    final steps = <WorkTaskStep>[];
    if (rawSteps is List) {
      for (final item in rawSteps) {
        if (item is! Map) continue;
        steps.add(
          WorkTaskStep(
            action: item['action'] as String? ?? '',
            reason: item['reason'] as String? ?? '',
            target: item['target'] as String?,
            args: (item['args'] as Map<String, dynamic>?) ?? const {},
          ),
        );
      }
    }
    final task = WorkTask(
      id:
          body['task_id'] as String? ??
          'task-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}',
      deviceId: 'local',
      originDeviceId: body['origin_device_id'] as String?,
      instruction: instruction,
      steps: steps,
      status: WorkTaskStatus.pending,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    final runtime = _TaskRuntime(task);
    // 控制端可携带会话级审批策略（对应 Octop HitlSessionPolicy）：
    // ask（默认每次询问）/ allow_all / allow_actions
    final rawPolicy = body['policy'];
    if (rawPolicy is Map) {
      runtime.policy = WorkGuardPolicy.fromJson(
        rawPolicy.cast<String, dynamic>(),
      );
    }
    _tasks[task.id] = runtime;
    // 异步执行，立即返回任务句柄
    unawaited(_runTask(runtime));
    return _json(200, <String, dynamic>{'ok': true, 'task': task.toJson()});
  }

  /// GET /work/task/{id}/events —— SSE 事件流
  ///
  /// 关键实现要点：
  /// - **context `shelf.io.buffer_output: false`**：dart:io 的 HttpResponse
  ///   默认缓冲输出（>64KB 才刷 socket），SSE 小帧会被卡住直到响应关闭。
  ///   必须显式关闭缓冲，否则事件流「连得上但不流动」。
  /// - 惰性发送（onListen 模式）：shelf 注册 body 监听时才补发历史事件，
  ///   避免「无监听者时 add+close 导致缓冲事件不流出」的 Dart Stream 语义陷阱。
  /// - 心跳注释帧：防止代理/网络设备掐断空闲长连接。
  /// - 任务终止时关闭事件总线，晚到的订阅者一次性收完历史即关闭。
  shelf.Response _handleTaskEvents(shelf.Request request) {
    if (!_authorized(request)) return _unauthorized();
    final taskId = request.params['taskId'];
    final runtime = _tasks[taskId];
    if (runtime == null) {
      return _json(404, <String, dynamic>{'ok': false, 'error': '任务不存在'});
    }
    StreamSubscription<Map<String, dynamic>>? liveSub;
    Timer? heartbeat;
    late final StreamController<List<int>> body;
    body = StreamController<List<int>>(
      onListen: () {
        for (final event in runtime.history) {
          body.add(utf8.encode(_sseFrame(event)));
        }
        if (runtime.finished) {
          body.close();
          return;
        }
        heartbeat = Timer.periodic(const Duration(seconds: 15), (_) {
          if (!body.isClosed) {
            body.add(const Utf8Encoder().convert(': keep-alive\n\n'));
          }
        });
        liveSub = runtime.events.stream.listen(
          (event) {
            if (!body.isClosed) body.add(utf8.encode(_sseFrame(event)));
          },
          onDone: () {
            heartbeat?.cancel();
            if (!body.isClosed) body.close();
          },
        );
      },
      onCancel: () {
        heartbeat?.cancel();
        liveSub?.cancel();
      },
    );
    return shelf.Response(
      200,
      headers: <String, String>{
        'Content-Type': 'text/event-stream; charset=utf-8',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
        'Access-Control-Allow-Origin': '*',
      },
      body: body.stream,
      // 关闭 dart:io 输出缓冲：SSE 帧必须即时刷到 socket
      context: const <String, Object>{'shelf.io.buffer_output': false},
    );
  }

  static String _sseFrame(Map<String, dynamic> event) =>
      'data: ${jsonEncode(event)}\n\n';

  /// POST /work/task/{id}/approve —— 审批回传
  Future<shelf.Response> _handleApprove(shelf.Request request) async {
    if (!_authorized(request)) return _unauthorized();
    final taskId = request.params['taskId'];
    final runtime = _tasks[taskId];
    if (runtime == null) {
      return _json(404, <String, dynamic>{'ok': false, 'error': '任务不存在'});
    }
    Map<String, dynamic> body;
    try {
      final raw = await request.readAsString();
      body =
          (raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw))
              as Map<String, dynamic>;
    } catch (_) {
      return _json(400, <String, dynamic>{
        'ok': false,
        'error': '请求体不是合法 JSON',
      });
    }
    final decision = body['decision'] as String? ?? 'deny';
    // allow_all / allow_action：写入会话策略（对应 Octop HITL 三态）
    if (decision == 'allow_all') {
      runtime.policy = const WorkGuardPolicy.allowAll();
    } else if (decision == 'allow_action') {
      final action = body['action'] as String?;
      if (action != null && action.isNotEmpty) {
        runtime.policy = runtime.policy.withAction(action);
      }
    }
    final allowed =
        decision == 'allow' ||
        decision == 'allow_all' ||
        decision == 'allow_action';
    final completer = runtime.approvalCompleter;
    runtime.approvalCompleter = null;
    completer?.complete(allowed);
    return _json(200, <String, dynamic>{'ok': true});
  }

  // ---------------------------------------------------------------- 执行引擎

  Future<void> _runTask(_TaskRuntime runtime) async {
    final task = runtime.task;
    final tier = WorkPermissions.tierById(_localTierId);
    if (tier == null) {
      _emit(runtime, <String, dynamic>{
        'type': 'task_failed',
        'error': '本机未配置有效权限档位',
      });
      return;
    }
    _emit(runtime, <String, dynamic>{
      'type': 'task_started',
      'task': task.toJson(),
    });

    for (var i = 0; i < task.steps.length; i++) {
      final step = task.steps[i];
      final decision = guard.evaluate(
        tier: tier,
        action: step.action,
        target: step.target,
        policy: runtime.policy,
      );

      if (decision.verdict == GuardVerdict.deny) {
        task.steps[i] = step.copyWith(
          status: WorkStepStatus.failed,
          error: decision.reason,
        );
        _emit(runtime, <String, dynamic>{
          'type': 'step_failed',
          'index': i,
          'reason': decision.reason,
        });
        _emit(runtime, <String, dynamic>{
          'type': 'task_failed',
          'error': '步骤 ${i + 1} 被拒绝：${decision.reason}',
        });
        return;
      }

      if (decision.verdict == GuardVerdict.requireApproval) {
        runtime.awaitingIndex = i;
        runtime.approvalCompleter = Completer<bool>();
        _emit(runtime, <String, dynamic>{
          'type': 'approval_request',
          'index': i,
          'action': step.action,
          'target': step.target,
          'reason': step.reason,
          'guard_reason': decision.reason,
        });
        final approved = await runtime.approvalCompleter!.future;
        runtime.awaitingIndex = -1;
        if (!approved) {
          task.steps[i] = step.copyWith(
            status: WorkStepStatus.rejected,
            error: '用户拒绝',
          );
          _emit(runtime, <String, dynamic>{
            'type': 'step_rejected',
            'index': i,
          });
          _emit(runtime, <String, dynamic>{
            'type': 'task_failed',
            'error': '步骤 ${i + 1} 被用户拒绝',
          });
          return;
        }
      }

      _emit(runtime, <String, dynamic>{'type': 'step_started', 'index': i});
      final result = await _execute(
        step.action,
        tier,
        target: step.target,
        args: step.args,
      );
      if (result.ok) {
        task.steps[i] = step.copyWith(
          status: WorkStepStatus.done,
          result: result.output,
        );
        _emit(runtime, <String, dynamic>{
          'type': 'step_done',
          'index': i,
          'output': result.output,
        });
      } else {
        task.steps[i] = step.copyWith(
          status: WorkStepStatus.failed,
          error: result.output,
        );
        _emit(runtime, <String, dynamic>{
          'type': 'step_failed',
          'index': i,
          'reason': result.output,
        });
        _emit(runtime, <String, dynamic>{
          'type': 'task_failed',
          'error': '步骤 ${i + 1} 执行失败：${result.output}',
        });
        return;
      }
    }

    _emit(runtime, <String, dynamic>{'type': 'task_done', 'task_id': task.id});
  }

  void _emit(_TaskRuntime runtime, Map<String, dynamic> event) {
    runtime.history.add(event);
    if (!runtime.events.isClosed) runtime.events.add(event);
    final type = event['type'] as String?;
    if (type == 'task_done' || type == 'task_failed') {
      runtime.finished = true;
      // 关闭事件总线：实时订阅者收到 done 后关闭各自 SSE body；
      // 晚到的订阅者走 history 补发路径（不消费 events.stream）。
      if (!runtime.events.isClosed) unawaited(runtime.events.close());
    }
  }

  // ---------------------------------------------------------------- 工具

  Map<String, dynamic> _deviceInfoJson() => <String, dynamic>{
    'id': 'local',
    'name': 'MOTA-${localPlatform.label}',
    'platform': localPlatform.id,
    'tier_id': _localTierId,
    'model': localPlatform.label,
  };

  static shelf.Response _json(int status, Map<String, dynamic> body) =>
      shelf.Response(
        status,
        headers: <String, String>{
          'Content-Type': 'application/json; charset=utf-8',
          'Access-Control-Allow-Origin': '*',
        },
        body: jsonEncode(body),
      );

  static shelf.Response _unauthorized() =>
      _json(401, <String, dynamic>{'ok': false, 'error': '未授权：请先配对'});
}
