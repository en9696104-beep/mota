import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../controllers/scripts_controller.dart';
import '../services/js_sandbox.dart';
import '../theme/app_theme.dart';

/// 脚本编辑页：编辑名称与代码、保存、沙箱运行、删除
class ScriptEditorPage extends StatefulWidget {
  const ScriptEditorPage({super.key});

  @override
  State<ScriptEditorPage> createState() => _ScriptEditorPageState();
}

class _ScriptEditorPageState extends State<ScriptEditorPage> {
  final ScriptsController _controller = Get.find<ScriptsController>();
  late final JsScript _script;
  late final TextEditingController _nameController;
  late final TextEditingController _codeController;

  JsExecResult? _result;
  bool _running = false;

  bool get _dirty =>
      _nameController.text != _script.name ||
      _codeController.text != _script.code;

  @override
  void initState() {
    super.initState();
    _script = Get.arguments as JsScript;
    _nameController = TextEditingController(text: _script.name);
    _codeController = TextEditingController(text: _script.code);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    _script.name = _nameController.text.trim().isEmpty
        ? '未命名脚本'
        : _nameController.text.trim();
    _script.code = _codeController.text;
    await _controller.save(_script);
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() => _running = true);
    // 有未保存修改时先落库，保证执行的就是编辑器里的代码
    if (_dirty) await _save();
    final result = await _controller.run(_script);
    if (!mounted) return;
    setState(() {
      _running = false;
      _result = result;
    });
  }

  Future<void> _confirmDelete() async {
    final ok = await Get.dialog<bool>(
      AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          '删除脚本',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          '确定要删除脚本“${_script.name}”吗？删除后不可恢复。',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13.5,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text(
              '取消',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            child: const Text(
              '删除',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _controller.delete(_script.id);
    if (mounted) Get.back();
    Get.snackbar(
      '已删除',
      _script.name,
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
    );
  }

  /// 有未保存修改时，退出前询问：保存 / 放弃 / 取消
  Future<bool> _confirmDiscard() async {
    final choice = await Get.dialog<String>(
      AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          '保存修改',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: const Text(
          '当前脚本有未保存的修改，是否保存？',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13.5,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text(
              '取消',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Get.back(result: 'discard'),
            child: const Text(
              '放弃',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Get.back(result: 'save'),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (choice == 'save') {
      await _save();
      return true;
    }
    return choice == 'discard';
  }

  void _onPopInvokedWithResult(bool didPop, Object? result) async {
    if (didPop) return;
    if (!_dirty) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final proceed = await _confirmDiscard();
    if (proceed && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: _onPopInvokedWithResult,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_script.name.isEmpty ? '编辑脚本' : _script.name),
          actions: [
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除脚本',
              onPressed: _confirmDelete,
            ),
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: '保存',
              onPressed: () async {
                await _save();
                if (!mounted) return;
                Get.snackbar(
                  '已保存',
                  _script.name,
                  snackPosition: SnackPosition.BOTTOM,
                  duration: const Duration(seconds: 2),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                onPressed: _running ? null : _run,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                icon: _running
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Icon(Icons.play_arrow, size: 18),
                label: Text(_running ? '运行中' : '运行'),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _nameController,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                cursorColor: AppColors.accent,
                decoration: const InputDecoration(
                  hintText: '脚本名称',
                  hintStyle: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 14,
                  ),
                  filled: true,
                  fillColor: AppColors.surface,
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
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _codeController,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontFamily: 'monospace',
                    height: 1.5,
                  ),
                  cursorColor: AppColors.accent,
                  decoration: const InputDecoration(
                    hintText: '// 在此编写 JavaScript',
                    hintStyle: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                    filled: true,
                    fillColor: AppColors.surface,
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
                  ),
                ),
              ),
            ),
            if (_result != null) _ResultPanel(result: _result!),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

/// 运行结果面板：状态、耗时、console 输出、返回值/错误
class _ResultPanel extends StatelessWidget {
  const _ResultPanel({required this.result});

  final JsExecResult result;

  @override
  Widget build(BuildContext context) {
    final ok = result.ok;
    final ret = result.returnValue;
    final hasReturn =
        ok && ret != null && ret.isNotEmpty && ret != 'undefined';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: result.timedOut
              ? AppColors.danger
              : (ok ? AppColors.accent : AppColors.danger),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ok ? Icons.check_circle_outline : Icons.error_outline,
                size: 15,
                color: ok ? AppColors.accent : AppColors.danger,
              ),
              const SizedBox(width: 6),
              Text(
                ok ? '执行成功' : (result.timedOut ? '执行超时' : '执行失败'),
                style: TextStyle(
                  color: ok ? AppColors.accent : AppColors.danger,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${result.durationMs} ms',
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () {
                  final text = [
                    if (result.hasOutput) result.output,
                    if (hasReturn) '返回值: $ret',
                    if (!ok && result.error != null) result.error,
                  ].join('\n');
                  Clipboard.setData(ClipboardData(text: text));
                  Get.snackbar(
                    '已复制',
                    '运行结果已复制到剪贴板',
                    snackPosition: SnackPosition.BOTTOM,
                    duration: const Duration(seconds: 2),
                  );
                },
                child: const Icon(
                  Icons.copy_rounded,
                  size: 14,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
          if (result.hasOutput) ...[
            const SizedBox(height: 8),
            const Text(
              'console 输出',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 10.5),
            ),
            const SizedBox(height: 4),
            SelectableText(
              result.output,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12.5,
                fontFamily: 'monospace',
                height: 1.45,
              ),
            ),
          ],
          if (hasReturn) ...[
            const SizedBox(height: 8),
            const Text(
              '返回值',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 10.5),
            ),
            const SizedBox(height: 4),
            SelectableText(
              ret,
              style: const TextStyle(
                color: AppColors.accent,
                fontSize: 12.5,
                fontFamily: 'monospace',
                height: 1.45,
              ),
            ),
          ],
          if (!ok && result.error != null) ...[
            const SizedBox(height: 8),
            const Text(
              '错误信息',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 10.5),
            ),
            const SizedBox(height: 4),
            SelectableText(
              result.error!,
              style: const TextStyle(
                color: AppColors.danger,
                fontSize: 12.5,
                fontFamily: 'monospace',
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
