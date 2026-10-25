/// MCP（Model Context Protocol）精简协议层
///
/// 实现 JSON-RPC 2.0 编解码 + MCP 核心类型，协议版本 2025-03-26
/// （Streamable HTTP 传输，适配 Android 单机场景，不依赖外部 SDK）。
library;

/// MCP 协议版本（initialize 握手声明）
const String mcpProtocolVersion = '2025-03-26';

/// JSON-RPC 2.0 标准错误码
class JsonRpcErrorCode {
  JsonRpcErrorCode._();

  static const int parseError = -32700;
  static const int invalidRequest = -32600;
  static const int methodNotFound = -32601;
  static const int invalidParams = -32602;
  static const int internalError = -32603;
}

/// MCP 方法名
class McpMethod {
  McpMethod._();

  static const String initialize = 'initialize';
  static const String initialized = 'notifications/initialized';
  static const String ping = 'ping';
  static const String toolsList = 'tools/list';
  static const String toolsCall = 'tools/call';
  static const String resourcesList = 'resources/list';
}

/// JSON-RPC 2.0 请求
class JsonRpcRequest {
  const JsonRpcRequest({
    required this.id,
    required this.method,
    this.params,
  });

  final Object? id; // String | int | null（null = 通知，无需响应）
  final String method;
  final Map<String, dynamic>? params;

  static JsonRpcRequest? fromJson(Map<String, dynamic> json) {
    final method = json['method'];
    if (method is! String || method.isEmpty) return null;
    final params = json['params'];
    return JsonRpcRequest(
      id: json['id'],
      method: method,
      params: params is Map ? params.cast<String, dynamic>() : null,
    );
  }
}

/// JSON-RPC 2.0 响应
class JsonRpcResponse {
  const JsonRpcResponse.success(this.id, Map<String, dynamic> result)
    : error = null,
      _result = result;

  JsonRpcResponse.failure(this.id, int code, String message)
    : error = <String, dynamic>{'code': code, 'message': message},
      _result = null;

  final Object? id;
  final Map<String, dynamic>? error;
  final Map<String, dynamic>? _result;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'jsonrpc': '2.0',
    'id': id,
    if (error != null) 'error': error else 'result': _result ?? <String, dynamic>{},
  };
}

/// MCP 工具定义（tools/list 返回）
class McpTool {
  const McpTool({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  final String name;
  final String description;

  /// JSON Schema（Object 类型）
  final Map<String, dynamic> inputSchema;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'description': description,
    'inputSchema': inputSchema,
  };

  static McpTool? fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    if (name is! String) return null;
    return McpTool(
      name: name,
      description: json['description'] as String? ?? '',
      inputSchema:
          (json['inputSchema'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{'type': 'object'},
    );
  }
}

/// MCP 工具调用结果（tools/call 返回）
class McpToolResult {
  const McpToolResult({required this.text, this.isError = false});

  final String text;
  final bool isError;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'content': <Map<String, dynamic>>[
      <String, dynamic>{'type': 'text', 'text': text},
    ],
    'isError': isError,
  };

  static McpToolResult fromJson(Map<String, dynamic> json) {
    final content = json['content'];
    final buffer = StringBuffer();
    if (content is List) {
      for (final part in content) {
        if (part is Map && part['type'] == 'text' && part['text'] is String) {
          if (buffer.isNotEmpty) buffer.write('\n');
          buffer.write(part['text'] as String);
        }
      }
    }
    return McpToolResult(
      text: buffer.toString(),
      isError: json['isError'] == true,
    );
  }
}

/// MCP initialize 返回的服务器信息
Map<String, dynamic> mcpInitializeResult({
  required String serverName,
  required String serverVersion,
}) {
  return <String, dynamic>{
    'protocolVersion': mcpProtocolVersion,
    'capabilities': <String, dynamic>{
      'tools': <String, dynamic>{'listChanged': false},
    },
    'serverInfo': <String, dynamic>{'name': serverName, 'version': serverVersion},
  };
}

/// MCP tools/list 返回
Map<String, dynamic> mcpToolsListResult(List<McpTool> tools) {
  return <String, dynamic>{
    'tools': tools.map((t) => t.toJson()).toList(),
  };
}
