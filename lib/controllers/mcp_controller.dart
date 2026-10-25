import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/mcp/mcp_protocol.dart';

/// 一个已配置的 MCP 服务器连接（含运行时状态）
class McpServerEntry {
  McpServerEntry({required this.url});

  /// Streamable HTTP 端点（如 http://192.168.1.5:3000/mcp）
  final String url;

  /// 连接是否就绪（initialize + tools/list 均成功）
  final connected = false.obs;

  /// 该服务器暴露的工具
  final tools = <McpTool>[].obs;

  /// 最近一次连接错误信息
  final error = ''.obs;
}

/// MCP 客户端：连接外部 MCP 服务器（Streamable HTTP），
/// 管理工具发现与调用，供本地模型的 function calling 使用
class McpController extends GetxController {
  final servers = <McpServerEntry>[].obs;

  static const String _prefsKey = 'mcp_servers_v1';
  static const Duration _rpcTimeout = Duration(seconds: 15);

  @override
  void onInit() {
    super.onInit();
    _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final urls = prefs.getStringList(_prefsKey) ?? const <String>[];
    servers.assignAll(urls.map((u) => McpServerEntry(url: u)));
    // 自动重连（静默；失败的标记为未连接，不阻塞 UI）
    for (final entry in servers.toList()) {
      _connect(entry);
    }
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _prefsKey,
      servers.map((s) => s.url).toList(),
    );
  }

  /// 规范化 URL：补全 http:// 前缀
  static String normalizeUrl(String raw) {
    var url = raw.trim();
    if (url.isEmpty) return url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    // 去掉末尾斜杠，保持端点干净
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  /// 添加并连接一个 MCP 服务器；连接失败返回 false（不入列表）
  Future<bool> addServer(String rawUrl) async {
    final url = normalizeUrl(rawUrl);
    if (url.isEmpty) return false;
    if (servers.any((s) => s.url == url)) {
      Get.snackbar('已存在', '该服务器已在列表中');
      return false;
    }
    final entry = McpServerEntry(url: url);
    final ok = await _connect(entry);
    if (!ok) return false;
    servers.add(entry);
    await _saveToPrefs();
    return true;
  }

  /// 移除服务器（不断开底层连接，MCP 无状态）
  Future<void> removeServer(McpServerEntry entry) async {
    servers.remove(entry);
    await _saveToPrefs();
  }

  /// 重连（刷新工具列表）
  Future<bool> reconnect(McpServerEntry entry) => _connect(entry);

  Future<bool> _connect(McpServerEntry entry) async {
    entry.error.value = '';
    try {
      final initResponse = await _rpc(
        entry.url,
        McpMethod.initialize,
        params: <String, dynamic>{
          'protocolVersion': mcpProtocolVersion,
          'capabilities': <String, dynamic>{},
          'clientInfo': <String, dynamic>{'name': 'MOTA', 'version': '1.0.0'},
        },
      );
      if (initResponse == null) {
        throw Exception('无响应');
      }
      if (initResponse['error'] is Map) {
        final err = initResponse['error'] as Map;
        throw Exception(err['message'] ?? 'initialize 失败');
      }
      final toolsResponse = await _rpc(entry.url, McpMethod.toolsList);
      final result = toolsResponse?['result'];
      final toolsJson = result is Map ? result['tools'] : null;
      entry.tools.assignAll(
        toolsJson is List
            ? toolsJson
                  .whereType<Map>()
                  .map((e) => McpTool.fromJson(e.cast<String, dynamic>()))
                  .whereType<McpTool>()
                  .toList()
            : <McpTool>[],
      );
      entry.connected.value = true;
      return true;
    } catch (e) {
      entry.connected.value = false;
      entry.tools.clear();
      entry.error.value = _friendlyError(e);
      return false;
    }
  }

  /// 调用某个服务器上的工具
  Future<McpToolResult> callTool(
    McpServerEntry entry,
    String name,
    Map<String, dynamic> arguments,
  ) async {
    final response = await _rpc(
      entry.url,
      McpMethod.toolsCall,
      params: <String, dynamic>{'name': name, 'arguments': arguments},
    );
    if (response == null) throw Exception('服务器无响应');
    if (response['error'] is Map) {
      final err = response['error'] as Map;
      throw Exception(err['message'] ?? '工具调用失败');
    }
    final result = response['result'];
    if (result is Map) {
      return McpToolResult.fromJson(result.cast<String, dynamic>());
    }
    throw Exception('返回格式不符');
  }

  /// 所有已连接服务器的工具（带来源服务器）
  List<({McpServerEntry server, McpTool tool})> get allTools {
    final list = <({McpServerEntry server, McpTool tool})>[];
    for (final server in servers) {
      if (!server.connected.value) continue;
      for (final tool in server.tools) {
        list.add((server: server, tool: tool));
      }
    }
    return list;
  }

  int get totalToolCount => allTools.length;

  /// 发送一条 JSON-RPC 请求；兼容纯 JSON 与 SSE（data: 前缀）两种响应
  Future<Map<String, dynamic>?> _rpc(
    String url,
    String method, {
    Map<String, dynamic>? params,
  }) async {
    final response = await Dio()
        .post<dynamic>(
          url,
          data: <String, dynamic>{
            'jsonrpc': '2.0',
            'id': DateTime.now().microsecondsSinceEpoch,
            'method': method,
            if (params != null) 'params': params,
          },
          options: Options(
            headers: <String, String>{
              'Accept': 'application/json, text/event-stream',
            },
            responseType: ResponseType.plain,
          ),
        )
        .timeout(_rpcTimeout);
    return _decodeRpcBody(response.data);
  }

  /// 解析响应体：优先 JSON；SSE 格式（data: {json}）时提取最后一条
  static Map<String, dynamic>? _decodeRpcBody(dynamic data) {
    if (data is Map) return data.cast<String, dynamic>();
    if (data is! String || data.trim().isEmpty) return null;
    final text = data.trim();
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {
      // 非纯 JSON：按 SSE 行解析
    }
    Map<String, dynamic>? last;
    for (final line in const LineSplitter().convert(text)) {
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload.isEmpty || payload == '[DONE]') continue;
      try {
        final decoded = jsonDecode(payload);
        if (decoded is Map) last = decoded.cast<String, dynamic>();
      } catch (_) {}
    }
    return last;
  }

  static String _friendlyError(Object e) {
    final text = e.toString();
    if (text.contains('TimeoutException') || text.contains('timed out')) {
      return '连接超时，请检查地址与网络';
    }
    if (text.contains('SocketException') || text.contains('Connection')) {
      return '无法连接，请检查地址是否可达';
    }
    return text.length > 80 ? '${text.substring(0, 80)}…' : text;
  }
}
