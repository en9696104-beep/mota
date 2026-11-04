import 'package:flutter/material.dart';

/// 模型名称文本：允许换行完整展示，**绝不显示省略号**。
///
/// 背景：模型名普遍较长（目录中最长 38 字符），此前多处使用
/// `maxLines: 1 + TextOverflow.ellipsis`，在手机端几乎必被截成 "…"。
///
/// 本组件统一处理：
/// - 允许换行到 [maxLines] 行（默认 3 行，覆盖全部内置模型名）
/// - 显式指定 `TextOverflow.clip`：即便极端长名超出也不画省略号
///   （同时避免继承 ListTile / DefaultTextStyle 的 ellipsis）
/// - 长按 / 悬停通过 Tooltip 给出完整名称兜底
///
/// 传 `maxLines: 1` 并配合外层 FittedBox（scaleDown）可用于 AppBar
/// 这类高度固定的场景，缩小字号也要把名字显示完整。
class ModelNameText extends StatelessWidget {
  const ModelNameText(
    this.name, {
    super.key,
    this.style,
    this.maxLines = 3,
    this.tooltip = true,
    this.textAlign,
  });

  final String name;

  final TextStyle? style;

  /// 最多行数；传 null 表示完全不限行（由父级高度决定）
  final int? maxLines;

  /// 是否启用长按 / 悬停查看完整名称
  final bool tooltip;

  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final child = Text(
      name,
      maxLines: maxLines,
      // 明确禁止省略号；超长时直接裁剪，配合 Tooltip 仍能看全名
      overflow: TextOverflow.clip,
      textAlign: textAlign,
      style: style,
    );
    if (!tooltip || name.isEmpty) return child;
    return Tooltip(
      message: name,
      waitDuration: const Duration(milliseconds: 350),
      showDuration: const Duration(seconds: 3),
      child: child,
    );
  }
}
