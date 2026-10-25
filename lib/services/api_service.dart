import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'llama_service.dart';
import 'mcp/mcp_server_service.dart';
import 'mcp/mcp_protocol.dart';
import '../work/services/work_agent_server.dart';

/// 本地 API 服务（对标 Ollama / LM Studio）
///
/// - 默认监听 127.0.0.1:8080（仅本机可访问）；开启「允许局域网访问」后监听 0.0.0.0，
///   同一 Wi-Fi 下的设备可直接调用
/// - OpenAI 兼容端点：POST /v1/chat/completions（支持 SSE 流式）、GET /v1/models
/// - 推理复用应用内同一个 LlamaService 实例（单引擎互斥，同时只允许一个生成任务）
class ApiService {
  ApiService._();

  static final ApiService instance = ApiService._();

  static const int _defaultPort = 8080;
  static const int _maxPortAttempts = 6; // 8080 ~ 8085

  HttpServer? _server;

  /// 服务是否运行中
  final RxBool isRunning = false.obs;

  /// 实际监听地址（127.0.0.1 或 0.0.0.0）
  final RxString bindAddress = '127.0.0.1'.obs;

  /// 实际监听端口（8080 被占用时自动递增）
  final RxInt port = _defaultPort.obs;

  /// 局域网 IPv4（供 UI 展示；未获取到时为 null）
  final RxString lanAddress = ''.obs;

  /// 是否允许局域网访问（0.0.0.0 监听）
  final RxBool allowLan = false.obs;

  /// 单引擎互斥：同时只允许一个生成任务（null 表示空闲）
  Future<void>? _generationLock;

  /// 获取生成锁（排队等待前一个任务完成；MCP 服务器等模块共用）
  Future<Completer<void>> acquireGenerationLock() async {
    while (_generationLock != null) {
      await _generationLock;
    }
    final completer = Completer<void>();
    _generationLock = completer.future;
    return completer;
  }

  /// 释放生成锁（幂等）
  void releaseGenerationLock(Completer<void> completer) {
    if (completer.isCompleted) return;
    completer.complete();
    if (_generationLock == completer.future) _generationLock = null;
  }

  late final Router _router = Router()
    ..post('/v1/chat/completions', _handleChatCompletions)
    ..get('/v1/models', _handleListModels)
    ..post('/mcp', _handleMcpPost)
    ..get('/mcp', _handleMcpSse)
    ..delete('/mcp', _handleMcpDelete)
    ..options('/<path|.*>', _handleOptions);

  /// Work 工作台被控端端点（配对/状态/任务/事件/审批）。
  /// 挂载后随 API 服务生命周期一起启停（需先在设置页开启服务）。
  bool _workMounted = false;

  void mountWorkRoutes() {
    if (_workMounted) return;
    _workMounted = true;
    WorkAgentServer.instance.mount(_router);
  }

  // ---------------------------------------------------------------- 生命周期

  /// 启动服务。[allowLan] 为 true 时监听 0.0.0.0（局域网可访问）。
  /// 返回是否启动成功；失败原因通过 [lastError] 查看。
  String? lastError;

  Future<bool> start({bool allowLan = false}) async {
    if (_server != null) return true;
    lastError = null;

    // Work 工作台被控端点（幂等：重复挂载同一路由由 shelf_router 去重容忍）
    mountWorkRoutes();

    final host = allowLan ? '0.0.0.0' : '127.0.0.1';
    HttpServer? server;
    Object? bindError;
    for (var attempt = 0; attempt < _maxPortAttempts; attempt++) {
      final tryPort = _defaultPort + attempt;
      try {
        server = await HttpServer.bind(
          InternetAddress(host),
          tryPort,
          shared: false,
        );
        port.value = tryPort;
        break;
      } catch (e) {
        bindError = e; // 端口占用等原因，尝试下一个端口
      }
    }
    if (server == null) {
      lastError = '无法绑定 $_defaultPort~${_defaultPort + _maxPortAttempts - 1} '
          '端口（$bindError）';
      return false;
    }

    _server = server;
    bindAddress.value = host;
    isRunning.value = true;

    // shelf 处理请求（handler 内的异常由 _safeHandler 兜底转 500）
    final handler = const shelf.Pipeline()
        .addMiddleware(shelf.logRequests())
        .addHandler(_router.call);
    shelf_io.serveRequests(server, (request) => _safeHandler(handler, request));

    if (allowLan) {
      lanAddress.value = await _detectLanIPv4() ?? '';
    }
    return true;
  }

  /// 停止服务
  Future<void> stop() async {
    final server = _server;
    _server = null;
    isRunning.value = false;
    if (server != null) {
      try {
        await server.close(force: true);
      } catch (_) {}
    }
  }

  /// 当前 API 基础地址（如 http://127.0.0.1:8080/v1）
  String get baseUrl => 'http://$_displayHost:${port.value}/v1';

  /// MCP Streamable HTTP 端点（如 http://127.0.0.1:8080/mcp）
  String get mcpUrl => 'http://$_displayHost:${port.value}/mcp';

  String get _displayHost =>
      bindAddress.value == '0.0.0.0' && lanAddress.value.isNotEmpty
          ? lanAddress.value
          : '127.0.0.1';

  /// 探测局域网 IPv4（优先 wlan 无线网卡）
  Future<String?> _detectLanIPv4() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        if (iface.name.startsWith('wlan') && iface.addresses.isNotEmpty) {
          return iface.addresses.first.address;
        }
      }
      for (final iface in interfaces) {
        if ((iface.name.startsWith('en') || iface.name.startsWith('eth')) &&
            iface.addresses.isNotEmpty) {
          return iface.addresses.first.address;
        }
      }
      if (interfaces.isNotEmpty && interfaces.first.addresses.isNotEmpty) {
        return interfaces.first.addresses.first.address;
      }
    } catch (_) {}
    return null;
  }

  // ---------------------------------------------------------------- 路由处理

  /// 顶层兜底：任何未捕获异常都转为 OpenAI 格式 500，绝不让服务器崩溃
  Future<shelf.Response> _safeHandler(
    shelf.Handler handler,
    shelf.Request request,
  ) async {
    try {
      return await handler(request);
    } catch (e) {
      return _openAiError(500, 'Internal server error: $e');
    }
  }

  /// POST /v1/chat/completions —— OpenAI 兼容对话端点（支持 SSE 流式）
  Future<shelf.Response> _handleChatCompletions(shelf.Request request) async {
    Map<String, dynamic> body;
    try {
      final raw = await request.readAsString();
      body = (raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw))
          as Map<String, dynamic>;
    } catch (_) {
      return _openAiError(400, 'Request body is not valid JSON');
    }

    final rawMessages = body['messages'];
    if (rawMessages is! List || rawMessages.isEmpty) {
      return _openAiError(400, '"messages" must be a non-empty array');
    }

    // OpenAI messages → LlamaTurn（content 支持字符串或多模态数组，取文本部分）
    final turns = <LlamaTurn>[];
    for (final item in rawMessages) {
      if (item is! Map) continue;
      final role = item['role'] as String? ?? 'user';
      final text = _extractText(item['content']);
      turns.add(LlamaTurn(role: role, content: text));
    }

    final model = body['model'] as String? ?? 'mota-local';
    final stream = body['stream'] == true;
    final temperature = (body['temperature'] as num?)?.toDouble() ?? 0.7;
    final maxTokens = (body['max_tokens'] as num?)?.toInt() ??
        (body['max_completion_tokens'] as num?)?.toInt() ??
        512;

    // 引擎未就绪（需先在 App 内打开一个模型）
    if (!LlamaService.instance.isLoaded) {
      return _openAiError(
        503,
        'No model loaded. Open a model in MOTA app first.',
      );
    }

    if (!stream) {
      // 非流式：聚合并返回完整 completion
      final lock = await ApiService.instance.acquireGenerationLock();
      try {
        final buffer = StringBuffer();
        await for (final token in LlamaService.instance.generateChatStream(
          turns,
          temperature: temperature,
          maxTokens: maxTokens,
        )) {
          buffer.write(token);
        }
        return shelf.Response.ok(
          jsonEncode(_completionJson(model, buffer.toString())),
          headers: _jsonHeaders,
        );
      } catch (e) {
        return _openAiError(500, 'Generation failed: $e');
      } finally {
        ApiService.instance.releaseGenerationLock(lock);
      }
    }

    // 流式 SSE：客户端断开时取消生成
    final lock = await ApiService.instance.acquireGenerationLock();
    final controller = StreamController<String>();
    final subscription =
        LlamaService.instance.generateChatStream(
          turns,
          temperature: temperature,
          maxTokens: maxTokens,
        ).listen(
          (token) {
            if (!controller.isClosed) {
              controller.add(
                'data: ${jsonEncode(_chunkJson(model, token))}\n\n',
              );
            }
          },
          onError: (Object e) {
            ApiService.instance.releaseGenerationLock(lock);
            if (!controller.isClosed) {
              controller.add(
                'data: ${jsonEncode(_chunkJson(model, '', finishReason: 'error', errorText: '$e'))}\n\n',
              );
              controller.add('data: [DONE]\n\n');
              controller.close();
            }
          },
          onDone: () {
            ApiService.instance.releaseGenerationLock(lock);
            if (!controller.isClosed) {
              controller.add(
                'data: ${jsonEncode(_chunkJson(model, '', finishReason: 'stop'))}\n\n',
              );
              controller.add('data: [DONE]\n\n');
              controller.close();
            }
          },
          cancelOnError: true,
        );
    controller.onCancel = () {
      subscription.cancel();
      ApiService.instance.releaseGenerationLock(lock);
      LlamaService.instance.stop();
    };

    return shelf.Response(
      200,
      headers: _sseHeaders,
      body: controller.stream.map((s) => utf8.encode(s)),
      // 关闭 dart:io 输出缓冲：SSE 帧必须即时刷到 socket
      // （默认缓冲 >64KB 才刷出，短回复会被卡到流结束）
      context: const <String, Object>{'shelf.io.buffer_output': false},
    );
  }

  /// GET /v1/models —— 列出当前已加载模型（OpenAI 客户端探测用）
  Future<shelf.Response> _handleListModels(shelf.Request request) async {
    final loaded = LlamaService.instance.isLoaded;
    final modelId = loaded
        ? (LlamaService.instance.loadedPath ?? 'mota-local')
              .split(Platform.pathSeparator)
              .last
        : 'mota-local';
    return shelf.Response.ok(
      jsonEncode(<String, dynamic>{
        'object': 'list',
        'data': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': modelId,
            'object': 'model',
            'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
            'owned_by': 'mota',
          },
        ],
      }),
      headers: _jsonHeaders,
    );
  }

  /// OPTIONS 预检（CORS）
  shelf.Response _handleOptions(shelf.Request request) =>
      shelf.Response(204, headers: _corsHeaders);

  // ---------------------------------------------------------------- MCP 端点

  /// POST /mcp —— MCP Streamable HTTP：客户端 → 服务器 JSON-RPC 请求
  Future<shelf.Response> _handleMcpPost(shelf.Request request) async {
    Map<String, dynamic> body;
    try {
      final raw = await request.readAsString();
      if (raw.isEmpty) {
        return _jsonRpcErrorResponse(
          null,
          JsonRpcErrorCode.invalidRequest,
          'Empty body',
        );
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return _jsonRpcErrorResponse(
          null,
          JsonRpcErrorCode.invalidRequest,
          'Expected a JSON-RPC object',
        );
      }
      body = decoded;
    } catch (_) {
      return _jsonRpcErrorResponse(
        null,
        JsonRpcErrorCode.parseError,
        'Parse error',
      );
    }

    final response = await McpServerService.instance.handle(body);
    if (response == null) {
      // 通知（无 id）：Accepted，无响应体
      return shelf.Response(202, headers: _jsonHeaders);
    }
    return shelf.Response.ok(
      jsonEncode(response.toJson()),
      headers: _jsonHeaders,
    );
  }

  /// GET /mcp —— MCP Streamable HTTP：服务器 → 客户端 SSE 通道
  /// （MOTA 暂无主动通知，保持连接 + 心跳即可）
  shelf.Response _handleMcpSse(shelf.Request request) {
    final controller = StreamController<String>();
    final timer = Stream.periodic(const Duration(seconds: 15)).listen((_) {
      if (!controller.isClosed) controller.add(': keep-alive\n\n');
    });
    controller.onCancel = () => timer.cancel();
    return shelf.Response(
      200,
      headers: _sseHeaders,
      body: controller.stream.map((s) => utf8.encode(s)),
      // 关闭 dart:io 输出缓冲：SSE 帧必须即时刷到 socket
      context: const <String, Object>{'shelf.io.buffer_output': false},
    );
  }

  /// DELETE /mcp —— 会话终止（无状态实现，直接 OK）
  shelf.Response _handleMcpDelete(shelf.Request request) =>
      shelf.Response(200, headers: _jsonHeaders);

  static shelf.Response _jsonRpcErrorResponse(
    Object? id,
    int code,
    String message,
  ) => shelf.Response.ok(
    jsonEncode(JsonRpcResponse.failure(id, code, message).toJson()),
    headers: _jsonHeaders,
  );

  // ---------------------------------------------------------------- 工具

  /// OpenAI content 可能是 String 或数组（多模态格式），统一提取纯文本
  static String _extractText(dynamic content) {
    if (content is String) return content;
    if (content is List) {
      final parts = <String>[];
      for (final part in content) {
        if (part is Map && part['type'] == 'text' && part['text'] is String) {
          parts.add(part['text'] as String);
        }
      }
      return parts.join('\n');
    }
    return '';
  }

  static Map<String, dynamic> _completionJson(String model, String text) {
    return <String, dynamic>{
      'id': 'chatcmpl-mota-${DateTime.now().millisecondsSinceEpoch}',
      'object': 'chat.completion',
      'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'model': model,
      'choices': <Map<String, dynamic>>[
        <String, dynamic>{
          'index': 0,
          'message': <String, dynamic>{'role': 'assistant', 'content': text},
          'finish_reason': 'stop',
        },
      ],
    };
  }

  /// SSE chunk：增量 delta；finishReason 非空时为终止帧
  static Map<String, dynamic> _chunkJson(
    String model,
    String delta, {
    String? finishReason,
    String? errorText,
  }) {
    return <String, dynamic>{
      'id': 'chatcmpl-mota-${DateTime.now().millisecondsSinceEpoch}',
      'object': 'chat.completion.chunk',
      'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'model': model,
      'choices': <Map<String, dynamic>>[
        <String, dynamic>{
          'index': 0,
          'delta': errorText != null
              ? <String, dynamic>{'error': errorText}
              : <String, dynamic>{'content': delta},
          'finish_reason': finishReason,
        },
      ],
    };
  }

  static Map<String, String> get _corsHeaders => <String, String>{
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': '*',
  };

  static Map<String, String> get _jsonHeaders => <String, String>{
    ..._corsHeaders,
    'Content-Type': 'application/json; charset=utf-8',
  };

  static Map<String, String> get _sseHeaders => <String, String>{
    ..._corsHeaders,
    'Content-Type': 'text/event-stream; charset=utf-8',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive',
  };

  /// OpenAI 格式错误响应
static shelf.Response _openAiError(int status, String message) => shelf.Response(
    status,
    headers: _jsonHeaders,
    body: jsonEncode(<String, dynamic>{
      'error': <String, dynamic>{
        'message': message,
        'type': 'api_error',
        'code': null,
      },
    }),
  );
}
