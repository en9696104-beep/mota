import 'package:flutter/material.dart';

import '../data/models/ai_model.dart';

/// 模型架构的极客风主题配色（暗黑模式）
///
/// - GGUF：纯白
/// - MNN：科技蓝 #00A0FF
/// - LiteRT：谷歌四色横向渐变（蓝/红/黄/绿）
/// - Apple：钛金属灰
class FormatTheme {
  FormatTheme._();

  /// 各架构主色（LiteRT 取渐变首色为代表色）
  static Color colorOf(ModelFormat format) {
    switch (format) {
      case ModelFormat.gguf:
        return const Color(0xFFFFFFFF);
      case ModelFormat.mnn:
        return const Color(0xFF00A0FF);
      case ModelFormat.litert:
        return const Color(0xFF4285F4);
      case ModelFormat.apple:
        return const Color(0xFF8E9096);
    }
  }

  /// LiteRT 谷歌四色渐变（筛选 Chip / 标签渐变底）
  static const List<Color> litertGradient = <Color>[
    Color(0xFF4285F4), // Google 蓝
    Color(0xFFEA4335), // Google 红
    Color(0xFFFBBC05), // Google 黄
    Color(0xFF34A853), // Google 绿
  ];

  /// 取某个架构的横向渐变（单色架构返回同色渐变，保证 API 统一）
  static Gradient gradientOf(ModelFormat format) {
    if (format == ModelFormat.litert) {
      return const LinearGradient(colors: litertGradient);
    }
    final c = colorOf(format);
    return LinearGradient(colors: [c, c]);
  }

  /// 未选中 Chip 的半透明底色（暗底上的弱填充）
  static Color softOf(ModelFormat format) {
    final c = colorOf(format);
    return c.withValues(alpha: 0.12);
  }

  /// 选中 Chip 的半透明底色（更明显的填充）
  static Color selectedOf(ModelFormat format) {
    final c = colorOf(format);
    return c.withValues(alpha: 0.22);
  }

  /// Chip 上的文字颜色（LiteRT 用白字 + 阴影保证渐变上的可读性）
  static Color textColorOf(ModelFormat format, {required bool selected}) {
    switch (format) {
      case ModelFormat.gguf:
        return const Color(0xFFFFFFFF);
      case ModelFormat.mnn:
        return const Color(0xFF00A0FF);
      case ModelFormat.apple:
        return const Color(0xFFB9BCC2);
      case ModelFormat.litert:
        return selected ? const Color(0xFFFFFFFF) : const Color(0xFFD8DEE9);
    }
  }
}
