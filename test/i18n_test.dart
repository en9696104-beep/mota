import 'package:flutter_test/flutter_test.dart';
import 'package:mota/i18n/app_translations.dart';
import 'package:mota/services/locale_service.dart';

void main() {
  group('i18n 契约', () {
    test('翻译表包含 zh_CN 与 en_US 两个语言', () {
      final keys = AppTranslations().keys;
      expect(keys.containsKey('zh_CN'), isTrue);
      expect(keys.containsKey('en_US'), isTrue);
    });

    test('zh_CN 为空映射（key 即中文原文，回退显示）', () {
      expect(AppTranslations().keys['zh_CN'], isEmpty);
    });

    test('en_US 映射的 key 均含中文（防误登记英文 key）', () {
      final en = AppTranslations().keys['en_US']!;
      expect(en, isNotEmpty);
      // 例外：能力标签 OCR 与语言选项 English 本身即非中文
      const allowedAscii = <String>{'OCR', 'English'};
      for (final key in en.keys) {
        final hasCjk = key.contains(RegExp(r'[\u4e00-\u9fa5]'));
        expect(hasCjk || allowedAscii.contains(key), isTrue,
            reason: 'key 应为中文原文: $key');
      }
    });

    test('en_US 值中保留 @参数 占位符与 key 一致', () {
      final en = AppTranslations().keys['en_US']!;
      String paramsOf(String s) =>
          RegExp(r'@[a-zA-Z]+').allMatches(s).map((m) => m[0]!).join(',');
      for (final entry in en.entries) {
        expect(paramsOf(entry.value), paramsOf(entry.key),
            reason: '占位符不一致: ${entry.key}');
      }
    });

    test('关键界面字符串已登记英文映射', () {
      final en = AppTranslations().keys['en_US']!;
      const mustHave = <String>[
        '我的模型',
        '模型商店',
        '历史对话',
        '工作',
        '工作台',
        '设置',
        '语言',
        '跟随系统',
        '多维度筛选',
        '能力',
        '领域',
      ];
      for (final key in mustHave) {
        expect(en.containsKey(key), isTrue, reason: '缺少映射: $key');
      }
    });

    test('LanguageMode 名称解析与往返', () {
      expect(LanguageMode.fromName('system'), LanguageMode.system);
      expect(LanguageMode.fromName('zh'), LanguageMode.zh);
      expect(LanguageMode.fromName('en'), LanguageMode.en);
      expect(LanguageMode.fromName('xx'), isNull);
      expect(LanguageMode.fromName(null), isNull);
    });
  });
}
