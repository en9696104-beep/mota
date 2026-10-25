import 'dart:convert';

import '../api_service.dart';
import '../llama_service.dart';
import '../model_repository.dart';
import 'mcp_protocol.dart';

/// MCP 服务器：把 MOTA 的本地模型能力通过 MCP 协议暴露给外部客户端
/// （Claude Desktop、其他 MCP Host 等，经 Streamable HTTP 访问 /mcp 端点）
///
/// 暴露的工具：
/// - chat_completion：用本地模型执行一轮对话（OpenAI messages 格式）
/// - list_models：列出已加载模型与商店目录概况
/// - get_model_info：查询商店中某个模型的元信息
class McpServerService {
  McpServerService._();

  static final McpServerService instance = McpServerService._();

  static const String _serverName = 'MOTA';
  static const String _serverVersion = '1.0.0';

  /// 工具目录
  static const List<McpTool> _tools = <McpTool>[
    McpTool(
      name: 'chat_completion',
      description: '用 MOTA 设备上加载的本地大模型执行一轮对话，'
          '返回完整回复文本。messages 为 OpenAI 格式数组。',
      inputSchema: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'messages': <String, dynamic>{
            'type': 'array',
            'description': 'OpenAI 格式消息数组，每项含 role 与 content',
            'items': <String, dynamic>{
              'type': 'object',
              'properties': <String, dynamic>{
                'role': <String, dynamic>{'type': 'string'},
                'content': <String, dynamic>{'type': 'string'},
              },
              'required': <String>['role', 'content'],
            },
          },
          'temperature': <String, dynamic>{
            'type': 'number',
            'description': '采样温度，默认 0.7',
          },
          'max_tokens': <String, dynamic>{
            'type': 'integer',
            'description': '最大生成 token 数，默认 512',
          },
        },
        'required': <String>['messages'],
      },
    ),
    McpTool(
      name: 'list_models',
      description: '列出当前设备已加载的模型与商店目录概况',
      inputSchema: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{},
      },
    ),
    McpTool(
      name: 'get_model_info',
      description: '查询商店目录中某个模型的元信息（厂商、领域、体积等）',
      inputSchema: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'model_id': <String, dynamic>{
            'type': 'string',
            'description': '模型 id（store 目录中的标识）',
          },
        },
        'required': <String>['model_id'],
      },
    ),
  ];

  List<McpTool> get tools => _tools;

  /// 处理一条 JSON-RPC 请求；通知类请求返回 null（无响应体）
  Future<JsonRpcResponse?> handle(
    Map<String, dynamic> body,
  ) async {
    final request = JsonRpcRequest.fromJson(body);
    if (request == null) {
      return JsonRpcResponse.failure(
        body['id'],
        JsonRpcErrorCode.invalidRequest,
        'Invalid JSON-RPC request',
      );
    }
    // 通知（无 id）：不返回响应
    if (request.id == null) return null;

    try {
      switch (request.method) {
        case McpMethod.initialize:
          return JsonRpcResponse.success(
            request.id,
            mcpInitializeResult(
              serverName: _serverName,
              serverVersion: _serverVersion,
            ),
          );
        case McpMethod.ping:
          return JsonRpcResponse.success(request.id, <String, dynamic>{});
        case McpMethod.toolsList:
          return JsonRpcResponse.success(
            request.id,
            mcpToolsListResult(tools),
          );
        case McpMethod.toolsCall:
          return await _handleToolCall(request);
        default:
          return JsonRpcResponse.failure(
            request.id,
            JsonRpcErrorCode.methodNotFound,
            'Method not found: ${request.method}',
          );
      }
    } catch (e) {
      return JsonRpcResponse.failure(
        request.id,
        JsonRpcErrorCode.internalError,
        'Internal error: $e',
      );
    }
  }

  Future<JsonRpcResponse> _handleToolCall(JsonRpcRequest request) async {
    final params = request.params;
    final name = params?['name'];
    if (name is! String || name.isEmpty) {
      return JsonRpcResponse.failure(
        request.id,
        JsonRpcErrorCode.invalidParams,
        '"name" is required',
      );
    }
    final arguments =
        (params?['arguments'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};

    if (!tools.any((t) => t.name == name)) {
      return JsonRpcResponse.success(
        request.id,
        McpToolResult(text: 'Unknown tool: $name', isError: true).toJson(),
      );
    }

    final result = switch (name) {
      'chat_completion' => await _toolChatCompletion(arguments),
      'list_models' => await _toolListModels(),
      'get_model_info' => _toolGetModelInfo(arguments),
      _ => McpToolResult(text: 'Unknown tool: $name', isError: true),
    };
    return JsonRpcResponse.success(request.id, result.toJson());
  }

  /// chat_completion：本地模型生成（与 OpenAI 端点共用引擎互斥锁）
  Future<McpToolResult> _toolChatCompletion(
    Map<String, dynamic> arguments,
  ) async {
    final rawMessages = arguments['messages'];
    if (rawMessages is! List || rawMessages.isEmpty) {
      return const McpToolResult(
        text: '"messages" must be a non-empty array',
        isError: true,
      );
    }
    final turns = <LlamaTurn>[];
    for (final item in rawMessages) {
      if (item is! Map) continue;
      turns.add(
        LlamaTurn(
          role: item['role'] as String? ?? 'user',
          content: item['content']?.toString() ?? '',
        ),
      );
    }
    if (!LlamaService.instance.isLoaded) {
      return const McpToolResult(
        text: 'No model loaded. Open a model in MOTA app first.',
        isError: true,
      );
    }

    final temperature = (arguments['temperature'] as num?)?.toDouble() ?? 0.7;
    final maxTokens = (arguments['max_tokens'] as num?)?.toInt() ?? 512;

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
      return McpToolResult(text: buffer.toString());
    } catch (e) {
      return McpToolResult(text: 'Generation failed: $e', isError: true);
    } finally {
      ApiService.instance.releaseGenerationLock(lock);
    }
  }

  Future<McpToolResult> _toolListModels() async {
    final loaded = LlamaService.instance.isLoaded;
    final loadedName = loaded
        ? (LlamaService.instance.loadedPath ?? '').split('/').last
        : null;
    final payload = <String, dynamic>{
      'loaded': loaded,
      'loaded_model': loadedName,
      'store_total': ModelRepository.to.models.length,
      'store_preview': ModelRepository.to.models
          .take(20)
          .map((m) => <String, dynamic>{'id': m.id, 'name': m.name})
          .toList(),
    };
    return McpToolResult(text: jsonEncode(payload));
  }

  McpToolResult _toolGetModelInfo(Map<String, dynamic> arguments) {
    final id = arguments['model_id'] as String?;
    if (id == null || id.isEmpty) {
      return const McpToolResult(text: '"model_id" is required', isError: true);
    }
    final model = ModelRepository.to.byId(id);
    if (model == null) {
      return McpToolResult(text: 'Model not found: $id', isError: true);
    }
    return McpToolResult(
      text: jsonEncode(<String, dynamic>{
        'id': model.id,
        'name': model.name,
        'author': model.author,
        'vendor': model.vendor,
        'domain': model.domain,
        'vertical': model.vertical,
        'license': model.license,
        'params': model.params,
        'quant': model.quant,
        'size_gb': model.sizeInGB,
        'github_stars': model.githubStars,
      }),
    );
  }
}
