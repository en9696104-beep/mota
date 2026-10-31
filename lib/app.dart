import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'i18n/app_translations.dart';
import 'routes/app_pages.dart';
import 'routes/app_routes.dart';
import 'services/locale_service.dart';
import 'theme/app_theme.dart';

/// MOTA 应用根组件
class MotaApp extends StatelessWidget {
  const MotaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'MOTA',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark, // 全局强制暗黑模式
      translations: AppTranslations(), // 中文原文即 key，未登记字符串回退中文
      fallbackLocale: const Locale('zh', 'CN'),
      locale: Get.find<LocaleService>().effectiveLocale,
      initialRoute: AppRoutes.main,
      getPages: AppPages.pages,
      defaultTransition: Transition.fade,
      transitionDuration: const Duration(milliseconds: 200),
    );
  }
}
