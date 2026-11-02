import 'package:flutter_test/flutter_test.dart';
import 'package:mota/services/memory_service.dart';
import 'package:mota/services/ocr_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 记忆系统 + OCR 缓存测试
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MemorySettings', () {
    test('JSON 往返保持全部开关', () {
      final settings = MemorySettings()
        ..enabled = true
        ..useGlobalMemory = true
        ..enableRecentChats = true
        ..enableTimeReminder = true
        ..extractionModelId = 'qwen-0.5b';
      final restored = MemorySettings.fromJson(settings.toJson());
      expect(restored.enabled, isTrue);
      expect(restored.useGlobalMemory, isTrue);
      expect(restored.enableRecentChats, isTrue);
      expect(restored.enableTimeReminder, isTrue);
      expect(restored.extractionModelId, 'qwen-0.5b');
    });

    test('默认值：全部关闭', () {
      final settings = MemorySettings();
      expect(settings.enabled, isFalse);
      expect(settings.useGlobalMemory, isFalse);
      expect(settings.extractionModelId, isNull);
    });
  });

  group('MemoryService.parseFacts', () {
    test('解析标准 JSON 数组', () {
      final facts = MemoryService.parseFacts('["用户偏好 Flutter", "项目名 MOTA"]');
      expect(facts, ['用户偏好 Flutter', '项目名 MOTA']);
    });

    test('容忍 ```json 代码块包裹', () {
      final facts = MemoryService.parseFacts(
        '好的，提取结果如下：\n```json\n["用户使用 Dart"]\n```',
      );
      expect(facts, ['用户使用 Dart']);
    });

    test('容忍前后缀文本', () {
      final facts = MemoryService.parseFacts(
        '提取结果：["用户在深圳工作"] 以上。',
      );
      expect(facts, ['用户在深圳工作']);
    });

    test('空数组 / 无数组输出返回空', () {
      expect(MemoryService.parseFacts('[]'), isEmpty);
      expect(MemoryService.parseFacts('没有值得记住的信息'), isEmpty);
      expect(MemoryService.parseFacts('{"broken": true'), isEmpty);
    });
  });

  group('MemoryService.describeGap', () {
    test('按量级人性化描述', () {
      expect(MemoryService.describeGap(const Duration(minutes: 5)), '5 分钟');
      expect(MemoryService.describeGap(const Duration(hours: 3)), '3 小时');
      expect(MemoryService.describeGap(const Duration(days: 2)), '2 天');
    });
  });

  group('OcrCache', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await OcrCache.clear();
    });

    test('写入后可命中', () async {
      await OcrCache.putByKey('k1', '识别文本');
      expect(await OcrCache.getByKey('k1'), '识别文本');
    });

    test('未写入的键不命中', () async {
      expect(await OcrCache.getByKey('missing'), isNull);
    });

    test('空文本不写入', () async {
      await OcrCache.putByKey('blank', '   ');
      expect(await OcrCache.getByKey('blank'), isNull);
    });

    test('容量上限淘汰最旧条目', () async {
      for (var i = 0; i < 70; i++) {
        await OcrCache.putByKey('k$i', 'text-$i');
        // 保证时间戳递增
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      // 最早的条目应被淘汰（上限 64）
      expect(await OcrCache.getByKey('k0'), isNull);
      expect(await OcrCache.getByKey('k69'), 'text-69');
    });

    test('clear 清空全部', () async {
      await OcrCache.putByKey('k1', 'a');
      await OcrCache.clear();
      expect(await OcrCache.getByKey('k1'), isNull);
    });
  });
}
