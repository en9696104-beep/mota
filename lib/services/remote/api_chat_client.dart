import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../llama_service.dart' show LlamaTurn;

/// OpenAI 兼容 Chat Completions 客户端（SSE 流式）。
///
/// 供导入的 API 模型使用：与本地 llama 引擎同一套 [LlamaTurn] 历史结构，
/// 生成侧替换为远程 HTTP 流式通道。
class ApiChatClient {
  ApiChatClient._();

  /// 由 baseUrl 推导完整端点：
  /// - 以 /chat/completions 结尾 → 原样使用
  /// - 以 /v1 结尾 → 追加 /chat/completions
  /// - 其余（如 https://api.deepseek.com）→ 追加 /v1/chat/completions
  static String buildEndpoint(String baseUrl) {
    var url = baseUrl.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.endsWith('/chat/completions')) return url;
    if (url.endsWith('/v1')) return '$url/chat/completions';
    return '$url/v1/chat/completions';
  }

  /// 流式对话。异常时抛出带状态码/响应片段的 Exception（上层可直接展示）。
  static Stream<String> streamChat({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<LlamaTurn> history,
    required double temperature,
  }) async* {
    final endpoint = buildEndpoint(baseUrl);
    final uri = Uri.tryParse(endpoint);
    if (uri == null || !uri.isAbsolute) {
      throw FormatException('API 地址不合法：$endpoint');
    }

    final body = jsonEncode(<String, dynamic>{
      'model': model,
      'messages': [
        for (final turn in history)
          <String, String>{'role': turn.role, 'content': turn.content},
      ],
      'temperature': temperature,
      'stream': true,
    });

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);
    try {
      final request = await client
          .postUrl(uri)
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw const SocketException('连接超时（30s）'),
          );
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      if (apiKey.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      }
      request.write(body);

      final response = await request.close();
      if (response.statusCode != 200) {
        final snippet = await response
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .take(5)
            .join('\n');
        throw HttpException(
          'API 返回 ${response.statusCode}：'
          '${snippet.length > 200 ? '${snippet.substring(0, 200)}…' : snippet}',
          uri: uri,
        );
      }

      // SSE 解析：data: {...} 行，[DONE] 结束；
      // 容错：忽略注释行（: 开头）与无法解析的行
      final lines = response
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith(':')) continue;
        if (!trimmed.startsWith('data:')) continue;
        final payload = trimmed.substring(5).trim();
        if (payload == '[DONE]') break;
        try {
          final json = jsonDecode(payload) as Map<String, dynamic>;
          final choices = json['choices'];
          if (choices is! List || choices.isEmpty) continue;
          final delta = (choices.first as Map)['delta'];
          if (delta is! Map) continue;
          final content = delta['content'];
          if (content is String && content.isNotEmpty) {
            yield content;
          }
        } catch (_) {
          // 单行坏数据：跳过
        }
      }
    } finally {
      client.close(force: true);
    }
  }
}
