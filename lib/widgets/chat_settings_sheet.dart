import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/chat_controller.dart';
import '../controllers/chat_settings_controller.dart';
import '../theme/app_theme.dart';

/// 打开「模型高级参数」底部抽屉
Future<void> showChatSettingsSheet() {
  return Get.bottomSheet(
    const ChatSettingsSheet(),
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
  );
}

/// 模型高级参数设置面板（对标 MNN Chat）
///
/// - 上下文长度：1024 / 2048 / 4096 下拉
/// - 系统提示词：多行输入，默认「你是一个诚实的中文助理」
/// - 发散度 Temperature：0.0 ~ 1.5 滑块，默认 0.7
/// - 线程数：1 ~ 8 滑块，默认 4
class ChatSettingsSheet extends StatefulWidget {
  const ChatSettingsSheet({super.key});

  @override
  State<ChatSettingsSheet> createState() => _ChatSettingsSheetState();
}

class _ChatSettingsSheetState extends State<ChatSettingsSheet> {
  final ChatSettingsController _settings = ChatSettingsController.instance;

  late int _contextSize;
  late TextEditingController _promptController;
  late double _temperature;
  late int _threads;

  /// 保存/热重载中（禁用按钮，显示 loading）
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // 表单初值 = 当前已生效参数
    _contextSize = _settings.contextSize.value;
    _promptController = TextEditingController(
      text: _settings.systemPrompt.value,
    );
    _temperature = _settings.temperature.value;
    _threads = _settings.threads.value;
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  /// 表单值是否与已生效参数一致
  bool get _isDirty =>
      _contextSize != _settings.contextSize.value ||
      _promptController.text.trim() != _settings.systemPrompt.value ||
      _temperature != _settings.temperature.value ||
      _threads != _settings.threads.value;

  Future<void> _onResetDefaults() async {
    await _settings.resetDefaults();
    setState(() {
      _contextSize = ChatSettingsController.defaultContextSize;
      _promptController.text = ChatSettingsController.defaultSystemPrompt;
      _temperature = ChatSettingsController.defaultTemperature;
      _threads = ChatSettingsController.defaultThreads;
    });
  }

  /// 保存并应用：持久化参数 → 模型热重载（卸载旧模型按新参数重载）
  Future<void> _onSave() async {
    if (_saving) return;
    setState(() => _saving = true);

    await _settings.save(
      contextSize: _contextSize,
      systemPrompt: _promptController.text,
      temperature: _temperature,
      threads: _threads,
    );

    // 仅当已进入聊天页且模型已下载时才触发热重载；否则参数已持久化，模型加载时自动生效
    var reloaded = false;
    if (Get.isRegistered<ChatController>()) {
      final chat = Get.find<ChatController>();
      if (chat.hasLocalModel) {
        await chat.reloadWithNewSettings();
        reloaded = true;
      }
    }

    if (!mounted) return;
    setState(() => _saving = false);
    Get.back(); // 关闭抽屉
    Get.snackbar(
      reloaded ? '新配置已应用' : '参数已保存',
      reloaded ? '模型已按新参数热重载' : '模型下载后将按新参数加载',
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 顶部把手
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
                '模型高级参数',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '调整后保存将热重载模型，立即生效',
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 20),

              // 上下文长度
              _SettingsSection(
                label: '上下文长度',
                hint: '上下文越长可记住的对话越多，但占用内存显著增加',
                child: DropdownButtonFormField<int>(
                  initialValue: _contextSize,
                  dropdownColor: AppColors.surfaceHigh,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                  ),
                  decoration: _inputDecoration(),
                  items: ChatSettingsController.contextSizeOptions
                      .map(
                        (size) => DropdownMenuItem<int>(
                          value: size,
                          child: Text('$size'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _contextSize = value);
                  },
                ),
              ),
              const SizedBox(height: 18),

              // 系统提示词
              _SettingsSection(
                label: '系统提示词',
                hint: '每轮对话前置的角色设定，影响模型的行为风格',
                child: TextField(
                  controller: _promptController,
                  maxLines: 3,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                  ),
                  cursorColor: AppColors.accent,
                  decoration: _inputDecoration().copyWith(
                    hintText: ChatSettingsController.defaultSystemPrompt,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: 18),

              // 发散度（Temperature）
              _SettingsSection(
                label: '发散度（Temperature）',
                hint: '越低回答越确定保守，越高越发散有创意',
                trailing: Text(
                  _temperature.toStringAsFixed(1),
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AppColors.accent,
                    inactiveTrackColor: AppColors.surfaceHigh,
                    thumbColor: AppColors.accent,
                    overlayColor: AppColors.accentSoft,
                    trackHeight: 4,
                  ),
                  child: Slider(
                    value: _temperature.clamp(0.0, 1.5),
                    min: 0.0,
                    max: 1.5,
                    divisions: 15,
                    label: _temperature.toStringAsFixed(1),
                    onChanged: (value) {
                      setState(() => _temperature = value);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // 线程数
              _SettingsSection(
                label: '线程数',
                hint: '推理并行度，建议不超过手机物理核心数',
                trailing: Text(
                  '$_threads',
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AppColors.accent,
                    inactiveTrackColor: AppColors.surfaceHigh,
                    thumbColor: AppColors.accent,
                    overlayColor: AppColors.accentSoft,
                    trackHeight: 4,
                  ),
                  child: Slider(
                    value: _threads.clamp(1, 8).toDouble(),
                    min: 1,
                    max: 8,
                    divisions: 7,
                    label: '$_threads',
                    onChanged: (value) {
                      setState(() => _threads = value.round());
                    },
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // 操作按钮
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _onResetDefaults,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('恢复默认'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving
                          ? null
                          : (_isDirty ? _onSave : null),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.black,
                        disabledBackgroundColor: AppColors.surfaceHigh,
                        disabledForegroundColor: AppColors.textTertiary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _saving
                          ? const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  '正在应用新配置并重载模型...',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            )
                          : const Text(
                              '保存并应用',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 设置区块：标签 + 说明 + 控件
class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.label,
    required this.hint,
    required this.child,
    this.trailing,
  });

  final String label;
  final String hint;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            if (trailing != null) trailing!,
          ],
        ),
        const SizedBox(height: 2),
        Text(
          hint,
          style: const TextStyle(
            color: AppColors.textTertiary,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

/// 暗黑主题输入框样式
InputDecoration _inputDecoration() {
  const border = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(10)),
    borderSide: BorderSide.none,
  );
  return const InputDecoration(
    filled: true,
    fillColor: AppColors.surfaceHigh,
    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 13),
    border: border,
    enabledBorder: border,
    focusedBorder: border,
  );
}
