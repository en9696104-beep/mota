import 'package:flutter/material.dart';

/// 全局配色（极简暗黑）
class AppColors {
  AppColors._();

  static const Color background = Color(0xFF09090B); // 页面背景
  static const Color surface = Color(0xFF131316); // 卡片 / 导航栏背景
  static const Color surfaceHigh = Color(0xFF1D1D22); // 次级卡片 / 标签
  static const Color border = Color(0xFF26262C); // 描边
  static const Color textPrimary = Color(0xFFF4F4F5); // 主文字
  static const Color textSecondary = Color(0xFF9B9BA5); // 次文字
  static const Color textTertiary = Color(0xFF5B5B65); // 弱文字
  static const Color accent = Color(0xFF00E5A0); // 主题色（薄荷绿）
  static const Color accentSoft = Color(0x1F00E5A0); // 主题色弱填充
  static const Color danger = Color(0xFFFF6B6B); // 危险 / 删除

  /// 头像渐变色，按 colorIndex 循环取用
  static const List<List<Color>> avatarGradients = <List<Color>>[
    <Color>[Color(0xFF3B82F6), Color(0xFF8B5CF6)],
    <Color>[Color(0xFF06B6D4), Color(0xFF22C55E)],
    <Color>[Color(0xFFF59E0B), Color(0xFFEF4444)],
    <Color>[Color(0xFFEC4899), Color(0xFF8B5CF6)],
    <Color>[Color(0xFF10B981), Color(0xFF3B82F6)],
    <Color>[Color(0xFF6366F1), Color(0xFFEC4899)],
  ];
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.accent,
        onPrimary: Colors.black,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.accent,
        unselectedItemColor: AppColors.textTertiary,
        selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
        unselectedLabelStyle: TextStyle(fontSize: 11),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
    );
  }
}
