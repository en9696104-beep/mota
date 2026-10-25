/// 控制端 HTTP 客户端 —— 配对、状态探测、任务下发、事件流、审批
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/work_permission.dart';
import '../models/work_task.dart';
import 'work_guard.dart';

/// 对端 /work/status 返回的快照
class WorkPeerStatus {
  const WorkPeerStatus({
    required this.ok,
    required this.tierId,
    required this.capabilities,
    required this.agentReady,
    this.tierLabel,
    this.deviceName,
    this.platform,
    this.error,
  });

  final bool ok;
  final String tierId;
  final String? tierLabel;
  final List<String> capabilities;
  final bool agentReady;
  final String? deviceName;
  final String? platform;
  final String? error;
}

/// 任务事件（SSE data 帧）
class WorkTaskEvent {
  const WorkTaskEvent(this.type, this.payload);

  final String type;
  final Map<String, dynamic> payload;
}

/// 控制端客户端：一个实例对应一台对端设备
class WorkClient {
  WorkClient(this.endpoint, {this.token});

  /// 对端端点（配对前可后补：先探测状态再配对）
  String endpoint;
  String? token;

  final http.Client _http = http.Client();

  Uri _uri(String path) => Uri.parse('$endpoint$path');

  Map<String, String> get _authHeaders => <String, String>{
        if (token != null) 'authorization': 'Bearer $token',
      };

  /// 配对：配对码换令牌
  Future<bool> pair({
    required String pairCode,
    required String deviceId,
    String? deviceName,
    WorkPlatform? platform,
  }) async {
    final resp = await _http.post(
      _uri('/work/pair'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(<String, dynamic>{
        'pair_code': pairCode,
        'device_id': deviceId,
        'device_name': deviceName,
        'platform': platform?.id,
      }),
    );
    if (resp.statusCode != 200) return false;
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (body['ok'] != true) return false;
    token = body['token'] as String?;
    return token != null;
  }

  /// 探测对端状态
  Future<WorkPeerStatus> status() async {
    try {
      final resp = await _http
          .get(_uri('/work/status'), headers: _authHeaders)
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 401) {
        return const WorkPeerStatus(
          ok: false,
          tierId: 'view_only',
          capabilities: <String>[],
          agentReady: false,
          error: '未授权：需重新配对',
        );
      }
      if (resp.statusCode != 200) {
        return WorkPeerStatus(
          ok: false,
          tierId: 'view_only',
          capabilities: const <String>[],
          agentReady: false,
          error: 'HTTP ${resp.statusCode}',
        );
      }
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final tier = body['tier'] as Map<String, dynamic>?;
      return WorkPeerStatus(
        ok: body['ok'] == true,
        tierId: tier?['id'] as String? ?? 'view_only',
        tierLabel: tier?['label'] as String?,
        capabilities:
            (tier?['capabilities'] as List?)?.cast<String>() ?? const <String>[],
        agentReady: body['agent_ready'] == true,
        deviceName: (body['device'] as Map<String, dynamic>?)?['name'] as String?,
        platform: (body['device'] as Map<String, dynamic>?)?['platform'] as String?,
      );
    } catch (e) {
      return WorkPeerStatus(
        ok: false,
        tierId: 'view_only',
        capabilities: const <String>[],
        agentReady: false,
        error: '$e',
      );
    }
  }

  /// 下发任务（控制端已拆解为步骤）。
  /// [policy] 为会话级审批策略：默认 ask（每步询问），可传 allowAll 直接放行。
  Future<WorkTask?> submitTask({
    required String instruction,
    required List<WorkTaskStep> steps,
    String? taskId,
    String? originDeviceId,
    WorkGuardPolicy? policy,
  }) async {
    final resp = await _http.post(
      _uri('/work/task'),
      headers: <String, String>{..._authHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode(<String, dynamic>{
        'task_id': taskId,
        'instruction': instruction,
        'origin_device_id': originDeviceId,
        'steps': steps.map((s) => s.toJson()).toList(),
        if (policy != null) 'policy': policy.toJson(),
      }),
    );
    if (resp.statusCode != 200) return null;
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (body['ok'] != true) return null;
    return WorkTask.fromJson(body['task'] as Map<String, dynamic>);
  }

  /// 订阅任务事件流（SSE）。返回订阅句柄，调用 cancel 结束。
  Stream<WorkTaskEvent> taskEvents(String taskId) {
    final controller = StreamController<WorkTaskEvent>();
    final request = http.Request('GET', _uri('/work/task/$taskId/events'))
      ..headers.addAll(_authHeaders);
    final response = _http.send(request);
    response.asStream().listen((resp) {
      if (resp.statusCode != 200) {
        controller.addError(StateError('HTTP ${resp.statusCode}'));
        controller.close();
        return;
      }
      resp.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (!line.startsWith('data: ')) return;
        try {
          final payload = jsonDecode(line.substring(6)) as Map<String, dynamic>;
          controller.add(WorkTaskEvent(
            payload['type'] as String? ?? 'unknown',
            payload,
          ));
        } catch (_) {}
      }, onDone: controller.close, onError: controller.addError);
    }, onError: controller.addError);
    return controller.stream;
  }

  /// 审批回传
  Future<bool> approve(
    String taskId, {
    required String decision,
    String? action,
  }) async {
    final resp = await _http.post(
      _uri('/work/task/$taskId/approve'),
      headers: <String, String>{..._authHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode(<String, dynamic>{
        'decision': decision,
        if (action != null) 'action': action,
      }),
    );
    return resp.statusCode == 200;
  }

  void close() => _http.close();
}
