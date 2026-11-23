import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../data/models/download_source.dart';
import '../theme/app_theme.dart';

/// 选择下载源底部面板（BottomSheet）
///
/// - 列出该模型可用的下载源（HF 官方 / HF 镜像 / 魔搭 / 手动上传）
/// - 可勾选「设为默认」，之后下载优先选中该源
/// - 返回选中的 [DownloadSource]；用户取消返回 null
class DownloadSourceSheet extends StatefulWidget {
  const DownloadSourceSheet({
    super.key,
    required this.sources,
    required this.initial,
  });

  /// 该模型可用的下载源列表
  final List<DownloadSource> sources;

  /// 默认选中的源（来自偏好，调用方已保证在 sources 内）
  final DownloadSource initial;

  /// 弹出面板；返回选中源或 null（取消）
  static Future<DownloadSource?> show({
    required List<DownloadSource> sources,
    required DownloadSource initial,
  }) {
    return Get.bottomSheet<DownloadSource>(
      DownloadSourceSheet(sources: sources, initial: initial),
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
    );
  }

  @override
  State<DownloadSourceSheet> createState() => _DownloadSourceSheetState();
}

class _DownloadSourceSheetState extends State<DownloadSourceSheet> {
  late DownloadSource _selected;
  bool _setAsDefault = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
  }

  IconData _iconOf(DownloadSource s) {
    switch (s) {
      case DownloadSource.hfOfficial:
        return Icons.public_rounded;
      case DownloadSource.hfMirror:
        return Icons.bolt_rounded;
      case DownloadSource.modelScope:
        return Icons.hub_rounded;
      case DownloadSource.localImport:
        return Icons.folder_open_rounded;
    }
  }

  void _confirm() {
    if (_setAsDefault) saveDefaultSource(_selected);
    Get.back<DownloadSource>(result: _selected);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部拖拽指示条
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '选择下载源',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '同一模型可选不同来源，HF 镜像国内访问更快',
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            // 源列表
            ...widget.sources.map((s) => _sourceTile(s)),
            const SizedBox(height: 12),
            // 设为默认
            GestureDetector(
              onTap: () => setState(() => _setAsDefault = !_setAsDefault),
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: Checkbox(
                      value: _setAsDefault,
                      onChanged: (v) =>
                          setState(() => _setAsDefault = v ?? false),
                      activeColor: AppColors.accent,
                      checkColor: Colors.black,
                      side: const BorderSide(color: AppColors.border),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '设为默认下载源',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            // 操作按钮
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Get.back(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: AppColors.border),
                      ),
                    ),
                    child: const Text(
                      '取消',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _confirm,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      _selected == DownloadSource.localImport ? '选择文件' : '开始下载',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sourceTile(DownloadSource s) {
    final isSelected = _selected == s;
    return GestureDetector(
      onTap: () => setState(() => _selected = s),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accentSoft : AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.accent : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              _iconOf(s),
              size: 20,
              color: isSelected ? AppColors.accent : AppColors.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.label.tr,
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.accent
                          : AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.hint.tr,
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle_rounded,
                size: 20,
                color: AppColors.accent,
              ),
          ],
        ),
      ),
    );
  }
}
