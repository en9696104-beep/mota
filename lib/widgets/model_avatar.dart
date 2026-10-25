import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 模型头像：首字母 + 渐变底色（无需图片资源）
class ModelAvatar extends StatelessWidget {
  const ModelAvatar({
    super.key,
    required this.name,
    required this.colorIndex,
    this.size = 46,
  });

  final String name;
  final int colorIndex;
  final double size;

  @override
  Widget build(BuildContext context) {
    const gradients = AppColors.avatarGradients;
    final gradient = gradients[colorIndex % gradients.length];
    final match = RegExp(r'[A-Za-z0-9]').firstMatch(name);
    final letter = match == null ? 'M' : match.group(0)!.toUpperCase();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
