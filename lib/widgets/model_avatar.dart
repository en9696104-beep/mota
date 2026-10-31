import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 作者/厂商 → 品牌图标资源名（assets/model_icons/{key}.png）
/// 图标来源：simple-icons 矢量、GitHub 组织头像、官网 favicon、主题字块
const Map<String, String> kAuthorIcons = {
  '阿里云 Qwen': 'qwen',
  'Qwen': 'qwen',
  'Google': 'google',
  '深度求索 DeepSeek': 'deepseek',
  'DeepSeek': 'deepseek',
  'Meta': 'meta',
  'Microsoft': 'microsoft',
  'Mistral AI': 'mistral',
  'HuggingFace': 'huggingface',
  '智谱 AI': 'zhipu',
  '面壁智能': 'openbmb',
  '智源 BAAI': 'baai',
  '医疗社区': 'medical',
  'IBM': 'ibm',
  'OpenAI': 'openai',
  '零一万物 01.AI': 'yi01',
  '上海AI实验室': 'shanghaiailab',
  '学术开源': 'academic',
  '百度': 'baidu',
  '金融社区': 'finance',
  'LG AI Research': 'lg',
  '法律社区': 'legal',
};

/// 按作者查品牌图标资源路径；未知作者返回 null（调用方回退字块头像）
String? iconAssetForAuthor(String? author) {
  if (author == null || author.isEmpty) return null;
  final key = kAuthorIcons[author];
  return key == null ? null : 'assets/model_icons/$key.png';
}

/// 模型头像：优先品牌 logo（白底圆角块），未知作者回退首字母 + 渐变底色
class ModelAvatar extends StatelessWidget {
  const ModelAvatar({
    super.key,
    required this.name,
    required this.colorIndex,
    this.author,
    this.size = 46,
  });

  final String name;
  final int colorIndex;

  /// 模型作者/厂商（匹配 kAuthorIcons 时展示品牌 logo）
  final String? author;

  final double size;

  @override
  Widget build(BuildContext context) {
    final asset = iconAssetForAuthor(author);
    if (asset != null) {
      return Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(size * 0.3),
          border: Border.all(color: AppColors.border),
        ),
        child: Image.asset(
          asset,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          // 图标缺失时不崩：回退到首字母块
          errorBuilder: (_, __, ___) => _LetterTile(
            name: name,
            colorIndex: colorIndex,
            size: size,
          ),
        ),
      );
    }
    return _LetterTile(name: name, colorIndex: colorIndex, size: size);
  }
}

/// 首字母 + 渐变底色（无品牌图标时的回退）
class _LetterTile extends StatelessWidget {
  const _LetterTile({
    required this.name,
    required this.colorIndex,
    required this.size,
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
