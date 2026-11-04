import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'model_name_text.dart';

import '../data/models/ai_model.dart';
import '../theme/app_theme.dart';
import '../theme/format_theme.dart';

/// 自定义模型导入确认面板（BottomSheet）
/// - 展示待导入文件名与体积
/// - 自定义名称输入
/// - 架构手动选择（默认 GGUF），带极客风配色
/// 返回 {name, format}；用户取消返回 null
class ImportFormatSheet extends StatefulWidget {
  const ImportFormatSheet({
    super.key,
    required this.fileName,
    required this.sizeLabel,
    this.defaultFormat = ModelFormat.gguf,
  });

  /// 选中的文件名（用于预填名称）
  final String fileName;

  /// 体积展示文案，如 "1.96 GB"
  final String sizeLabel;

  /// 默认选中的架构（按后缀预推断，未知时 GGUF）
  final ModelFormat defaultFormat;

  /// 弹出面板，返回 {name: String, format: ModelFormat} 或 null
  static Future<Map<String, dynamic>?> show({
    required String fileName,
    required String sizeLabel,
    ModelFormat defaultFormat = ModelFormat.gguf,
  }) {
    return Get.bottomSheet<Map<String, dynamic>>(
      ImportFormatSheet(
        fileName: fileName,
        sizeLabel: sizeLabel,
        defaultFormat: defaultFormat,
      ),
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
    );
  }

  @override
  State<ImportFormatSheet> createState() => _ImportFormatSheetState();
}

class _ImportFormatSheetState extends State<ImportFormatSheet> {
  late final TextEditingController _nameController;
  late ModelFormat _selected;

  @override
  void initState() {
    super.initState();
    // 预填名称：去掉后缀的文件名
    final dot = widget.fileName.lastIndexOf('.');
    final base = dot > 0 ? widget.fileName.substring(0, dot) : widget.fileName;
    _nameController = TextEditingController(text: base);
    _selected = widget.defaultFormat;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _confirm() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      Get.snackbar('名称不能为空', '请为模型输入一个名称', snackPosition: SnackPosition.BOTTOM);
      return;
    }
    Get.back<Map<String, dynamic>>(result: {'name': name, 'format': _selected});
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 键盘弹起时跟随上移
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
              '导入本地模型',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            ModelNameText(
              '${widget.fileName} · ${widget.sizeLabel}',
              maxLines: 3,
              tooltip: false,
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            // 名称输入
            const Text(
              '模型名称',
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _nameController,
              autofocus: true,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
              ),
              cursorColor: AppColors.accent,
              decoration: const InputDecoration(
                hintText: '输入模型名称',
                hintStyle: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 13,
                ),
                filled: true,
                fillColor: AppColors.surfaceHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                  borderSide: BorderSide(color: AppColors.accent),
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
              ),
            ),
            const SizedBox(height: 18),
            // 架构选择
            const Text(
              '选择架构',
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ModelFormat.values.map((format) {
                final isSelected = _selected == format;
                return GestureDetector(
                  onTap: () => setState(() => _selected = format),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      gradient: (format == ModelFormat.litert && isSelected)
                          ? FormatTheme.gradientOf(format)
                          : null,
                      color: format == ModelFormat.litert
                          ? (isSelected ? null : FormatTheme.softOf(format))
                          : (isSelected
                                ? FormatTheme.selectedOf(format)
                                : FormatTheme.softOf(format)),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? FormatTheme.colorOf(format)
                            : FormatTheme.colorOf(
                                format,
                              ).withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isSelected) ...[
                          Icon(
                            Icons.check,
                            size: 13,
                            color: FormatTheme.textColorOf(
                              format,
                              selected: true,
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          format.label,
                          style: TextStyle(
                            color: FormatTheme.textColorOf(
                              format,
                              selected: isSelected,
                            ),
                            fontSize: 12.5,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 6),
            Text(
              _formatHint(_selected),
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 11,
                height: 1.5,
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
                    child: const Text(
                      '确认导入',
                      style: TextStyle(fontWeight: FontWeight.w600),
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

  /// 各架构的引擎接入状态提示
  String _formatHint(ModelFormat format) {
    switch (format) {
      case ModelFormat.gguf:
        return 'GGUF（llama.cpp 引擎）：导入后可直接开始对话。';
      case ModelFormat.mnn:
        return 'MNN 引擎正在适配中，导入后可管理文件，暂无法直接对话。';
      case ModelFormat.litert:
        return 'LiteRT 引擎正在适配中，导入后可管理文件，暂无法直接对话。';
      case ModelFormat.apple:
        return 'Apple Core ML 引擎正在适配中，导入后可管理文件，暂无法直接对话。';
    }
  }
}
