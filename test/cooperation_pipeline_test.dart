// 合作系统 / 群聊 / ASR 数据层契约测试
//
// 覆盖：
// 1. ModelCapability 推导（domain/vertical/tags → 能力集合）
// 2. AiModel capabilities / projectorUrl 的 JSON 往返
// 3. CooperationConfig 持久化序列化与按角色修改
// 4. 商店数据完整性（新模型 URL / 能力 / 投影器一致性）

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:mota/data/models/ai_model.dart';
import 'package:mota/services/cooperation_pipeline.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ModelCapability 推导', () {
    test('多模态视觉模型：chat + vision', () {
      final model = AiModel.fromJson({
        'id': 'v',
        'name': 'Vision',
        'domain': '多模态',
        'vertical': '图像',
        'tags': ['图像'],
      });
      final caps = model.effectiveCapabilities;
      expect(caps, contains(ModelCapability.chat));
      expect(caps, contains(ModelCapability.vision));
    });

    test('OCR 标签推导出 ocr 能力', () {
      final model = AiModel.fromJson({
        'id': 'o',
        'name': 'OCR-Model',
        'domain': '多模态',
        'vertical': '图像',
        'tags': ['OCR', '文档'],
      });
      expect(model.hasCapability(ModelCapability.ocr), true);
      expect(model.hasCapability(ModelCapability.vision), true);
    });

    test('语音识别 / 合成标签推导', () {
      final asr = AiModel.fromJson({
        'id': 'a',
        'name': 'ASR',
        'domain': '全模态',
        'tags': ['语音识别'],
      });
      expect(asr.hasCapability(ModelCapability.asr), true);

      final tts = AiModel.fromJson({
        'id': 't',
        'name': 'TTS',
        'domain': '全模态',
        'tags': ['语音合成'],
      });
      expect(tts.hasCapability(ModelCapability.tts), true);
    });

    test('Embedding / Rerank / 安全 / 代码 / 推理标签推导', () {
      expect(
        AiModel.fromJson({'id': '1', 'name': 'E', 'domain': '文本', 'tags': ['Embedding']})
            .hasCapability(ModelCapability.embedding),
        true,
      );
      expect(
        AiModel.fromJson({'id': '2', 'name': 'R', 'domain': '文本', 'tags': ['Rerank']})
            .hasCapability(ModelCapability.rerank),
        true,
      );
      expect(
        AiModel.fromJson({'id': '3', 'name': 'Guard', 'domain': '文本', 'tags': ['安全']})
            .hasCapability(ModelCapability.security),
        true,
      );
      expect(
        AiModel.fromJson({'id': '4', 'name': 'C', 'domain': '文本', 'vertical': '代码'})
            .hasCapability(ModelCapability.code),
        true,
      );
      expect(
        AiModel.fromJson({'id': '5', 'name': 'R1', 'domain': '文本', 'vertical': '数学'})
            .hasCapability(ModelCapability.reasoning),
        true,
      );
    });

    test('显式 capabilities 优先于推导', () {
      final model = AiModel.fromJson({
        'id': 'x',
        'name': 'X',
        'domain': '文本',
        'tags': ['OCR'], // 推导会得到 ocr
        'capabilities': ['chat', 'security'], // 显式声明优先
      });
      final caps = model.effectiveCapabilities;
      expect(caps, contains(ModelCapability.chat));
      expect(caps, contains(ModelCapability.security));
      expect(caps, isNot(contains(ModelCapability.ocr)));
    });

    test('未知能力名被忽略', () {
      final model = AiModel.fromJson({
        'id': 'y',
        'name': 'Y',
        'domain': '文本',
        'capabilities': ['chat', 'not-a-capability'],
      });
      expect(model.effectiveCapabilities, [ModelCapability.chat]);
    });
  });

  group('AiModel capabilities / projector JSON 往返', () {
    test('fromJson/toJson 保留能力与投影器字段', () {
      final model = AiModel.fromJson({
        'id': 'ocr',
        'name': 'DeepSeek-OCR',
        'domain': '多模态',
        'capabilities': ['vision', 'ocr'],
        'projectorUrl': 'https://example.com/mmproj.gguf',
        'projectorSizeMB': 461,
      });
      expect(model.needsProjector, true);
      expect(model.projectorSizeMB, 461);

      final json = model.toJson();
      expect(json['capabilities'], ['vision', 'ocr']);
      expect(json['projectorUrl'], 'https://example.com/mmproj.gguf');

      final round = AiModel.fromJson(json);
      expect(round.capabilities,
          [ModelCapability.vision, ModelCapability.ocr]);
      expect(round.projectorUrl, model.projectorUrl);
      expect(round.projectorSizeMB, 461);
    });

    test('无投影器模型 needsProjector 为 false', () {
      final model = AiModel.fromJson({'id': 'p', 'name': 'P', 'domain': '文本'});
      expect(model.needsProjector, false);
      expect(model.projectorSizeMB, 0);
    });

    test('copyWith 保留能力字段', () {
      final model = AiModel.fromJson({
        'id': 'c',
        'name': 'C',
        'domain': '多模态',
        'capabilities': ['vision'],
        'projectorUrl': 'https://example.com/mm.gguf',
      });
      final copied = model.copyWith(githubStars: 42);
      expect(copied.capabilities, [ModelCapability.vision]);
      expect(copied.projectorUrl, 'https://example.com/mm.gguf');
      expect(copied.githubStars, 42);
    });
  });

  group('CooperationConfig 序列化', () {
    test('默认值：关闭且无角色', () {
      final config = CooperationConfig();
      expect(config.enabled, false);
      expect(config.chatModelId, null);
      expect(config.configuredAuxRoleCount, 0);
    });

    test('JSON 往返保留全部角色', () {
      final config = CooperationConfig(
        enabled: true,
        chatModelId: 'chat-1',
        ocrModelId: 'ocr-1',
        asrModelId: 'asr-1',
        ttsModelId: 'tts-1',
        embeddingModelId: 'emb-1',
        rerankModelId: 're-1',
        securityModelId: 'sec-1',
      );
      final json = jsonDecode(jsonEncode(config.toJson())) as Map<String, dynamic>;
      final restored = CooperationConfig.fromJson(json);
      expect(restored.enabled, true);
      expect(restored.chatModelId, 'chat-1');
      expect(restored.ocrModelId, 'ocr-1');
      expect(restored.asrModelId, 'asr-1');
      expect(restored.ttsModelId, 'tts-1');
      expect(restored.embeddingModelId, 'emb-1');
      expect(restored.rerankModelId, 're-1');
      expect(restored.securityModelId, 'sec-1');
      expect(restored.configuredAuxRoleCount, 6);
    });

    test('modelIdFor / setModelIdFor / copyWithModel 按角色读写', () {
      final config = CooperationConfig();
      for (final role in PipelineRole.values) {
        config.setModelIdFor(role, '${role.name}-model');
        expect(config.modelIdFor(role), '${role.name}-model');
      }
      final next = config.copyWithModel(PipelineRole.ocr, 'ocr-2');
      expect(next.ocrModelId, 'ocr-2');
      // 原对象不受影响
      expect(config.ocrModelId, 'ocr-model');
      // 清除角色
      final cleared = config.copyWithModel(PipelineRole.chat, null);
      expect(cleared.chatModelId, null);
    });

    test('角色要求的模型能力映射正确', () {
      expect(PipelineRole.chat.requiredCapability, ModelCapability.chat);
      expect(PipelineRole.ocr.requiredCapability, ModelCapability.ocr);
      expect(PipelineRole.asr.requiredCapability, ModelCapability.asr);
      expect(PipelineRole.tts.requiredCapability, ModelCapability.tts);
      expect(PipelineRole.embedding.requiredCapability, ModelCapability.embedding);
      expect(PipelineRole.rerank.requiredCapability, ModelCapability.rerank);
      expect(PipelineRole.security.requiredCapability, ModelCapability.security);
    });

    test('损坏 JSON 回退默认配置', () async {
      // fromJson 对空 map 返回默认值
      final config = CooperationConfig.fromJson(const {});
      expect(config.enabled, false);
    });
  });

  group('商店数据完整性（assets/store_data.json）', () {
    test('全部模型具备 capabilities，多模态模型带投影器地址', () async {
      final raw = await rootBundle.loadString('assets/store_data.json');
      final list = (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
      expect(list.length, greaterThanOrEqualTo(100));

      for (final m in list) {
        final model = AiModel.fromJson(m);
        // 每个模型至少有一个能力
        expect(
          model.effectiveCapabilities.isNotEmpty,
          true,
          reason: '模型 ${model.id} 无任何能力',
        );
        // OCR / ASR / TTS / 视觉模型必须配投影器地址（无投影器则图像/音频输入必然失败）
        final needsProjector = model.hasCapability(ModelCapability.ocr) ||
            model.hasCapability(ModelCapability.asr) ||
            model.hasCapability(ModelCapability.tts) ||
            model.hasCapability(ModelCapability.vision);
        if (needsProjector) {
          expect(
            model.projectorUrl,
            isNotNull,
            reason: '模型 ${model.id} 缺投影器地址',
          );
        }
        // 有投影器的模型必须声明投影器体积
        if (model.projectorUrl != null) {
          expect(
            model.projectorSizeMB,
            greaterThan(0),
            reason: '模型 ${model.id} 缺投影器体积',
          );
        }
      }
    });

    test('新增能力模型已入商店', () async {
      final raw = await rootBundle.loadString('assets/store_data.json');
      final list = (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
      final byCap = <ModelCapability, int>{};
      for (final m in list) {
        for (final c in AiModel.fromJson(m).effectiveCapabilities) {
          byCap[c] = (byCap[c] ?? 0) + 1;
        }
      }
      expect(byCap[ModelCapability.ocr]! >= 3, true);
      expect(byCap[ModelCapability.asr]! >= 2, true);
      expect(byCap[ModelCapability.tts]! >= 1, true);
      expect(byCap[ModelCapability.embedding]! >= 2, true);
      expect(byCap[ModelCapability.rerank]! >= 1, true);
      expect(byCap[ModelCapability.security]! >= 1, true);
    });
  });
}
