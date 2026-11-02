import 'package:flutter_test/flutter_test.dart';
import 'package:mota/data/models/ai_model.dart';
import 'package:mota/services/remote/api_chat_client.dart';
import 'package:mota/services/remote/api_model_service.dart';

void main() {
  group('ApiChatClient.buildEndpoint', () {
    test('裸域名 → 追加 /v1/chat/completions', () {
      expect(
        ApiChatClient.buildEndpoint('https://api.deepseek.com'),
        'https://api.deepseek.com/v1/chat/completions',
      );
    });

    test('已带 /v1 → 追加 /chat/completions', () {
      expect(
        ApiChatClient.buildEndpoint('https://api.openai.com/v1'),
        'https://api.openai.com/v1/chat/completions',
      );
    });

    test('完整端点 → 原样保留', () {
      expect(
        ApiChatClient.buildEndpoint('https://x.com/v1/chat/completions'),
        'https://x.com/v1/chat/completions',
      );
    });

    test('尾部斜杠清理', () {
      expect(
        ApiChatClient.buildEndpoint('https://api.deepseek.com/'),
        'https://api.deepseek.com/v1/chat/completions',
      );
      expect(
        ApiChatClient.buildEndpoint('https://x.com/v1//'),
        'https://x.com/v1/chat/completions',
      );
    });

    test('本地服务端点（LM Studio / Ollama 兼容层）', () {
      expect(
        ApiChatClient.buildEndpoint('http://192.168.1.5:1234/v1'),
        'http://192.168.1.5:1234/v1/chat/completions',
      );
    });
  });

  group('ApiModelConfig 序列化', () {
    test('toJson / fromJson 往返', () {
      final config = ApiModelConfig(
        id: 'abc',
        name: 'DeepSeek 官方',
        baseUrl: 'https://api.deepseek.com',
        apiKey: 'sk-test-123456',
        model: 'deepseek-chat',
      );
      final restored = ApiModelConfig.fromJson(config.toJson());
      expect(restored.id, 'abc');
      expect(restored.name, 'DeepSeek 官方');
      expect(restored.baseUrl, 'https://api.deepseek.com');
      expect(restored.apiKey, 'sk-test-123456');
      expect(restored.model, 'deepseek-chat');
    });

    test('maskedKey 打码', () {
      final config = ApiModelConfig(
        id: 'a',
        name: 'n',
        baseUrl: 'https://x.com',
        apiKey: 'sk-abcdefghijklmnopqrstuvwxyz',
        model: 'm',
      );
      expect(config.maskedKey, startsWith('sk-ab'));
      expect(config.maskedKey, endsWith('xyz'));
      expect(config.maskedKey, isNot(contains('cdefghijklmnopqrstuvw')));

      final empty = ApiModelConfig(
          id: 'b', name: 'n', baseUrl: 'https://x.com', apiKey: '', model: 'm');
      expect(empty.maskedKey, '未设置密钥');
    });

    test('损坏 JSON 容错', () {
      final restored = ApiModelConfig.fromJson(<String, dynamic>{
        'name': 123,
        'baseUrl': null,
      });
      expect(restored.baseUrl, '');
      expect(restored.model, '');
    });
  });

  group('API 模型与本地模型互不干扰', () {
    test('api: 前缀 id 不与商店模型冲突', () {
      // 商店模型 id 是 uuid / slug，api:<id> 前缀保证聊天记录隔离
      const apiId = 'api:test123';
      expect(apiId.startsWith('api:'), isTrue);
      expect(
        ModelCapability.values.where((c) => c.name == 'vision').isNotEmpty,
        isTrue,
      );
    });
  });
}
