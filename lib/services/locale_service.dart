import 'dart:io' show Platform;
import 'dart:ui' show Locale;

import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 界面语言模式
enum LanguageMode {
  system('跟随系统'),
  zh('中文'),
  en('English');

  const LanguageMode(this.label);

  final String label;

  static LanguageMode? fromName(String? name) {
    if (name == null) return null;
    for (final m in LanguageMode.values) {
      if (m.name == name) return m;
    }
    return null;
  }
}

/// 语言服务：管理「跟随系统 / 中文 / English」三态选择并持久化。
///
/// 切换即时生效（Get.updateLocale）；「跟随系统」解析设备 locale，
/// 非中文系统统一落到 English（未覆盖语言由 fallbackLocale 回退中文）。
class LocaleService extends GetxService {
  static const String _prefsKey = 'app_locale_mode_v1';

  /// 当前选择模式
  final mode = LanguageMode.system.obs;

  static const Locale _zhCn = Locale('zh', 'CN');
  static const Locale _enUs = Locale('en', 'US');

  Future<LocaleService> init() async {
    final prefs = await SharedPreferences.getInstance();
    mode.value =
        LanguageMode.fromName(prefs.getString(_prefsKey)) ?? LanguageMode.system;
    return this;
  }

  /// 初始构建时生效的 locale（GetMaterialApp 的 locale 参数用）
  Locale get effectiveLocale {
    switch (mode.value) {
      case LanguageMode.system:
        return _deviceLocale();
      case LanguageMode.zh:
        return _zhCn;
      case LanguageMode.en:
        return _enUs;
    }
  }

  /// 切换语言模式：持久化并立即生效
  Future<void> setMode(LanguageMode m) async {
    if (mode.value == m) return;
    mode.value = m;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, m.name);
    _apply();
  }

  void _apply() {
    switch (mode.value) {
      case LanguageMode.system:
        Get.updateLocale(_deviceLocale());
      case LanguageMode.zh:
        Get.updateLocale(_zhCn);
      case LanguageMode.en:
        Get.updateLocale(_enUs);
    }
  }

  /// 设备 locale：中文系（zh_*）→ zh_CN，其余 → en_US
  Locale _deviceLocale() {
    final code = Get.deviceLocale?.languageCode ??
        Platform.localeName.split('_').first.toLowerCase();
    return code.startsWith('zh') ? _zhCn : _enUs;
  }
}
