import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../controllers/mcp_controller.dart';
import '../routes/app_routes.dart';
import '../services/api_service.dart';
import '../services/ask_user_service.dart';
import '../services/locale_service.dart';
import '../services/memory_service.dart';
import '../services/model_repository.dart';
import '../services/remote/api_model_service.dart';
import '../services/update_checker.dart';
import '../theme/app_theme.dart';
import '../widgets/model_avatar.dart';
import '../widgets/model_name_text.dart';

/// 设置页：版本信息、检查更新、商店数据来源
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _checking = false;

  /// 检查更新：多源拉远端版本 JSON → 比较 → 有新版本弹窗（可直接跳转 download_url）
  Future<void> _checkUpdate() async {
    if (_checking) return;
    setState(() => _checking = true);
    final result = await UpdateChecker.check();
    if (!mounted) return;
    setState(() => _checking = false);

    if (!result.ok) {
      Get.snackbar(
        '检查更新失败'.tr,
        (result.reason ?? '网络异常或更新配置无效，请稍后重试').tr,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 4),
      );
      return;
    }
    final info = result.info!;
    if (!UpdateChecker.isNewer(info.version, AppConfig.currentVersion)) {
      Get.snackbar(
        '已是最新版本'.tr,
        '当前版本 v@v'.trParams({'v': AppConfig.currentVersion}),
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    Get.dialog(
      AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          '发现新版本 v@v'.trParams({'v': info.version}),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '更新内容'.tr,
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              info.releaseNotes.isEmpty ? '（未提供更新说明）'.tr : info.releaseNotes,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '当前版本 v@v'.trParams({'v': AppConfig.currentVersion}),
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 11,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text(
              '暂不更新'.tr,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.black,
            ),
            onPressed: () => _openDownload(info.downloadUrl),
            child: Text(
              '立即更新'.tr,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  /// 打开远端下载地址（系统浏览器）
  Future<void> _openDownload(String url) async {
    Get.back(); // 先关闭弹窗
    final uri = Uri.tryParse(url);
    if (uri == null) {
      Get.snackbar('打开失败'.tr, '下载地址无效'.tr, snackPosition: SnackPosition.BOTTOM);
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      Get.snackbar(
        '打开失败'.tr,
        '未找到可处理该链接的应用'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('设置'.tr)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          const _SectionTitle('通用'),
          const _LanguageTile(),
          const SizedBox(height: 20),
          const _SectionTitle('记忆'),
          const _MemorySection(),
          const SizedBox(height: 20),
          const _SectionTitle('对话'),
          const _AskSection(),
          const SizedBox(height: 20),
          const _SectionTitle('API 模型'),
          const _ApiModelsSection(),
          const SizedBox(height: 20),
          const _SectionTitle('插件'),
          const _DshSection(),
          const SizedBox(height: 20),
          const _SectionTitle('关于'),
          const _InfoTile(
            icon: Icons.verified_outlined,
            title: '当前版本',
            value: 'v${AppConfig.currentVersion}',
          ),
          const SizedBox(height: 8),
          _ActionTile(
            icon: Icons.system_update_alt_outlined,
            title: '检查更新',
            subtitle: '从远端版本配置检查是否有新版本',
            loading: _checking,
            onTap: _checkUpdate,
          ),
          const SizedBox(height: 20),
          const _ApiSection(),
          const SizedBox(height: 20),
          const _McpClientSection(),
          const SizedBox(height: 20),
          const _SectionTitle('JS 脚本'),
          _ActionTile(
            icon: Icons.code_outlined,
            title: '脚本管理',
            subtitle: '在 QuickJS 沙箱中编写并运行 JavaScript',
            loading: false,
            onTap: () => Get.toNamed(AppRoutes.scripts),
          ),
          const SizedBox(height: 8),
          const _HintText(
            '模型在对话中输出 javascript 代码块时会自动在沙箱中执行，'
            '结果反馈给模型继续推理；也可以在这里手动管理脚本。'
            '沙箱限制：5 秒超时、64MB 内存，无网络与文件访问。',
          ),
          const SizedBox(height: 20),
          const _SectionTitle('商店数据'),
          Obx(
            () => _InfoTile(
              icon: Icons.cloud_outlined,
              title: '数据来源',
              value: ModelRepository.to.dataSource.value,
            ),
          ),
          const SizedBox(height: 8),
          Obx(
            () => _InfoTile(
              icon: Icons.inventory_2_outlined,
              title: '模型数量',
              value: '@n 个'.trParams({
                'n': '${ModelRepository.to.models.length}',
              }),
            ),
          ),
          const SizedBox(height: 8),
          const _HintText(
            '商店数据启动时自动从远端同步，失败时使用本地缓存，'
            '断网时使用 App 内置数据，全程无需手动操作。',
          ),
        ],
      ),
    );
  }
}

/// 界面语言选择：跟随系统 / 中文 / English（即时生效）
class _LanguageTile extends StatelessWidget {
  const _LanguageTile();

  Future<void> _pick() async {
    final service = Get.find<LocaleService>();
    final current = service.mode.value;
    final selected = await Get.dialog<LanguageMode>(
      AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          '语言'.tr,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        content: RadioGroup<LanguageMode>(
          groupValue: service.mode.value,
          onChanged: (v) => Get.back(result: v),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final m in LanguageMode.values)
                RadioListTile<LanguageMode>(
                  value: m,
                  activeColor: AppColors.accent,
                  title: Text(
                    m.label.tr,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: m == LanguageMode.system
                      ? Text(
                          _systemLanguageName(),
                          style: const TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 11,
                          ),
                        )
                      : null,
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text(
              '取消'.tr,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
    if (selected != null && selected != current) {
      await service.setMode(selected);
    }
  }

  static String _systemLanguageName() {
    final code = Get.deviceLocale?.languageCode ?? '';
    return code.startsWith('zh') ? '中文' : 'English';
  }

  @override
  Widget build(BuildContext context) {
    final service = Get.find<LocaleService>();
    return GestureDetector(
      onTap: _pick,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.language, size: 18, color: AppColors.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '语言'.tr,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '选择界面语言'.tr,
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Obx(
              () => Text(
                service.mode.value.label.tr,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text.tr,
        style: const TextStyle(
          color: AppColors.textTertiary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title.tr,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13.5,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.loading,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.tr,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle.tr,
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (loading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.accent,
                ),
              )
            else
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: AppColors.textTertiary,
              ),
          ],
        ),
      ),
    );
  }
}

class _HintText extends StatelessWidget {
  const _HintText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        text.tr,
        style: const TextStyle(
          color: AppColors.textTertiary,
          fontSize: 11,
          height: 1.6,
        ),
      ),
    );
  }
}

/// 「记忆」区块：主开关 + 高级选项 + 提取模型 + 管理入口。
/// 开关语义对齐 RikkaHub 记忆设置（enableMemory / useGlobalMemory /
/// enableRecentChatsReference / enableTimeReminder）。
class _MemorySection extends StatelessWidget {
  const _MemorySection();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final memory = MemoryService.to;
      final settings = memory.settings.value;
      return Column(
        children: [
          _SwitchTile(
            icon: Icons.psychology_outlined,
            title: '启用记忆',
            subtitle: '模型跨对话记住你的偏好与背景，对话更连贯',
            value: settings.enabled,
            onChanged: (v) {
              final next = MemorySettings()
                ..enabled = v
                ..useGlobalMemory = settings.useGlobalMemory
                ..enableRecentChats = settings.enableRecentChats
                ..enableTimeReminder = settings.enableTimeReminder
                ..extractionModelId = settings.extractionModelId;
              memory.updateSettings(next);
            },
          ),
          if (settings.enabled) ...[
            const SizedBox(height: 8),
            _SwitchTile(
              icon: Icons.public_outlined,
              title: '使用全局记忆',
              subtitle: '开启后所有模型共享同一记忆池；关闭则每个模型独立记忆',
              value: settings.useGlobalMemory,
              onChanged: (v) {
                final next = MemorySettings()
                  ..enabled = settings.enabled
                  ..useGlobalMemory = v
                  ..enableRecentChats = settings.enableRecentChats
                  ..enableTimeReminder = settings.enableTimeReminder
                  ..extractionModelId = settings.extractionModelId;
                memory.updateSettings(next);
              },
            ),
            const SizedBox(height: 8),
            _SwitchTile(
              icon: Icons.history_outlined,
              title: '最近对话引用',
              subtitle: '让模型了解最近几轮对话的主题，保持连续性',
              value: settings.enableRecentChats,
              onChanged: (v) {
                final next = MemorySettings()
                  ..enabled = settings.enabled
                  ..useGlobalMemory = settings.useGlobalMemory
                  ..enableRecentChats = v
                  ..enableTimeReminder = settings.enableTimeReminder
                  ..extractionModelId = settings.extractionModelId;
                memory.updateSettings(next);
              },
            ),
            const SizedBox(height: 8),
            _SwitchTile(
              icon: Icons.schedule_outlined,
              title: '时间提醒',
              subtitle: '告诉模型距上次对话过去了多久',
              value: settings.enableTimeReminder,
              onChanged: (v) {
                final next = MemorySettings()
                  ..enabled = settings.enabled
                  ..useGlobalMemory = settings.useGlobalMemory
                  ..enableRecentChats = settings.enableRecentChats
                  ..enableTimeReminder = v
                  ..extractionModelId = settings.extractionModelId;
                memory.updateSettings(next);
              },
            ),
            const SizedBox(height: 8),
            _ActionTile(
              icon: Icons.folder_open_outlined,
              title: '记忆管理',
              subtitle: '查看、编辑或手动添加记忆条目',
              loading: false,
              onTap: () => Get.toNamed(AppRoutes.memory),
            ),
            const SizedBox(height: 8),
            _ExtractionModelTile(settings: settings),
            const SizedBox(height: 8),
            const _HintText(
              '每轮对话结束后，提取模型会分析对话并把值得记住的信息存为独立条目，'
              '下次对话前自动注入上下文。提取用快速小模型即可，本地推理无额外费用。',
            ),
          ],
        ],
      );
    });
  }
}

/// 记忆提取模型选择行
class _ExtractionModelTile extends StatelessWidget {
  const _ExtractionModelTile({required this.settings});

  final MemorySettings settings;

  String _label() {
    if (settings.extractionModelId == null) return '自动（最小的已下载模型）';
    final model = ModelRepository.to.byId(settings.extractionModelId!);
    return model?.name ?? '模型 ${settings.extractionModelId}';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _pick(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.speed_outlined, size: 18, color: AppColors.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '记忆提取模型',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _label(),
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final memory = MemoryService.to;
    final candidates = memory.downloadedChatModels();
    if (candidates.isEmpty) {
      Get.snackbar(
        '没有可用模型',
        '请先在商店下载对话模型',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                '选择记忆提取模型（建议小而快的模型）',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.auto_awesome,
                size: 20,
                color: AppColors.accent,
              ),
              title: const Text(
                '自动（最小的已下载模型）',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
              ),
              trailing: settings.extractionModelId == null
                  ? const Icon(
                      Icons.check_circle,
                      color: AppColors.accent,
                      size: 20,
                    )
                  : null,
              onTap: () => Navigator.of(ctx).pop(''),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: candidates.length,
                itemBuilder: (_, index) {
                  final model = candidates[index];
                  final selected = model.id == settings.extractionModelId;
                  return ListTile(
                    // 允许标题 2 行，避免长模型名被 ListTile 隐式截断
                    isThreeLine: true,
                    leading: ModelAvatar(
                      name: model.name,
                      colorIndex: model.colorIndex,
                      author: model.author,
                      size: 32,
                    ),
                    title: ModelNameText(
                      model.name,
                      maxLines: 2,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      '${model.params} · ${model.sizeLabel}',
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                    trailing: selected
                        ? const Icon(
                            Icons.check_circle,
                            color: AppColors.accent,
                            size: 20,
                          )
                        : null,
                    onTap: () => Navigator.of(ctx).pop(model.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null) return; // 点外部关闭：不修改
    final next = MemorySettings()
      ..enabled = settings.enabled
      ..useGlobalMemory = settings.useGlobalMemory
      ..enableRecentChats = settings.enableRecentChats
      ..enableTimeReminder = settings.enableTimeReminder
      ..extractionModelId = picked.isEmpty ? null : picked;
    await MemoryService.to.updateSettings(next);
  }
}

/// 「插件」区块：DSH（DeepSeek Harness）插件兼容层入口
class _DshSection extends StatelessWidget {
  const _DshSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ActionTile(
          icon: Icons.extension_outlined,
          title: 'DSH 插件',
          subtitle: '安装并管理 DeepSeek Harness 兼容插件',
          loading: false,
          onTap: () => Get.toNamed(AppRoutes.dshPlugins),
        ),
        const SizedBox(height: 8),
        const _HintText(
          '兼容 DeepSeek Harness 插件格式（package.json + cordis.patch.yml + apply(ctx)）。'
          '插件运行在无网络、无文件访问的 JS 沙箱中，注册的工具会出现在模型可用工具列表里。',
        ),
      ],
    );
  }
}

/// 「本地 API 服务」区块：开关、局域网访问、地址展示（对标 Ollama / LM Studio）
class _ApiSection extends StatelessWidget {
  const _ApiSection();

  Future<void> _toggleService(bool value) async {
    final api = ApiService.instance;
    if (value) {
      final ok = await api.start(allowLan: api.allowLan.value);
      if (!ok) {
        Get.snackbar(
          '启动失败'.tr,
          api.lastError ?? '未知错误'.tr,
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } else {
      await api.stop();
    }
  }

  Future<void> _toggleLan(bool value) async {
    final api = ApiService.instance;
    api.allowLan.value = value;
    // 服务运行中：按新的监听地址重启
    if (api.isRunning.value) {
      await api.stop();
      await api.start(allowLan: value);
    }
  }

  void _copyAddress(String url) {
    Clipboard.setData(ClipboardData(text: url));
    Get.snackbar(
      '已复制'.tr,
      url,
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final api = ApiService.instance;
    return Obx(() {
      final running = api.isRunning.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle('本地 API 服务'),
          _SwitchTile(
            icon: Icons.dns_outlined,
            title: '开启本地 API',
            subtitle: 'OpenAI 兼容接口，需先在 App 内加载模型',
            value: running,
            onChanged: _toggleService,
          ),
          if (running) ...[
            const SizedBox(height: 8),
            _SwitchTile(
              icon: Icons.wifi_outlined,
              title: '允许局域网访问',
              subtitle: '同一 Wi-Fi 下的设备可直接调用本机 API',
              value: api.allowLan.value,
              onChanged: _toggleLan,
            ),
            const SizedBox(height: 8),
            _AddressTile(
              url: api.baseUrl,
              lanHint: api.allowLan.value && api.lanAddress.value.isNotEmpty
                  ? '局域网地址 · @p 端口'.trParams({'p': '${api.port.value}'})
                  : '仅本机访问 · @p 端口'.trParams({'p': '${api.port.value}'}),
              onCopy: () => _copyAddress(api.baseUrl),
            ),
            const SizedBox(height: 8),
            _AddressTile(
              url: api.mcpUrl,
              lanHint: 'MCP 服务器端点 · 供 Claude Desktop 等 MCP 客户端连接',
              onCopy: () => _copyAddress(api.mcpUrl),
            ),
          ],
          const SizedBox(height: 8),
          const _HintText(
            '开启后，第三方工具（Cherry Studio、LobeChat 等）'
            '将 Base URL 设为上述地址、模型任选即可调用本机算力；'
            'Claude Desktop 等 MCP 客户端可连接 /mcp 端点使用 MOTA 工具。',
          ),
        ],
      );
    });
  }
}

/// 「MCP 客户端」区块：连接外部 MCP 服务器，让本地模型获得工具能力
class _McpClientSection extends StatelessWidget {
  const _McpClientSection();

  Future<void> _showAddDialog() async {
    final controller = TextEditingController();
    final url = await Get.dialog<String>(
      AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          '添加 MCP 服务器'.tr,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '输入 MCP 服务器的 Streamable HTTP 端点地址'.tr,
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
              ),
              cursorColor: AppColors.accent,
              decoration: const InputDecoration(
                hintText: 'http://192.168.1.5:3000/mcp',
                hintStyle: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 13,
                ),
                filled: true,
                fillColor: AppColors.surfaceHigh,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text(
              '取消'.tr,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Get.back(result: controller.text.trim()),
            child: Text('连接'.tr),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    final ok = await Get.find<McpController>().addServer(url);
    if (ok) {
      final entry = Get.find<McpController>().servers.lastWhere(
        (s) => s.url == McpController.normalizeUrl(url),
      );
      Get.snackbar(
        '连接成功'.tr,
        '发现 @n 个工具'.trParams({'n': '${entry.tools.length}'}),
        snackPosition: SnackPosition.BOTTOM,
      );
    } else {
      final error = Get.find<McpController>().servers
          .where((s) => s.url == McpController.normalizeUrl(url))
          .map((s) => s.error.value)
          .firstOrNull;
      Get.snackbar(
        '连接失败'.tr,
        error ?? '请检查地址与网络'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mcp = Get.find<McpController>();
    return Obx(() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const _SectionTitle('MCP 客户端'),
              const Spacer(),
              Text(
                '@n 个工具可用'.trParams({'n': '${mcp.totalToolCount}'}),
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (mcp.servers.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.extension_outlined,
                    size: 18,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '尚未连接任何 MCP 服务器\n连接后，本地模型即可调用外部工具'.tr,
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            ...mcp.servers.map((entry) => _McpServerCard(entry: entry)),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _showAddDialog,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: const BorderSide(color: AppColors.accent),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('添加服务器'),
          ),
          const SizedBox(height: 8),
          const _HintText(
            'MCP（Model Context Protocol）让模型调用外部工具。'
            '在电脑上运行任意 MCP 服务器后填入其 HTTP 地址即可，'
            '需手机与电脑在同一 Wi-Fi。',
          ),
        ],
      );
    });
  }
}

/// MCP 服务器条目卡片
class _McpServerCard extends StatelessWidget {
  const _McpServerCard({required this.entry});

  final McpServerEntry entry;

  @override
  Widget build(BuildContext context) {
    final mcp = Get.find<McpController>();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: entry.connected.value
                  ? AppColors.accent
                  : AppColors.textTertiary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Obx(
                  () => Text(
                    entry.connected.value
                        ? '@n 个工具'.trParams({'n': '${entry.tools.length}'})
                        : (entry.error.value.isNotEmpty
                              ? entry.error.value
                              : '未连接'.tr),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: entry.connected.value
                          ? AppColors.textTertiary
                          : AppColors.danger,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.refresh,
              size: 16,
              color: AppColors.textSecondary,
            ),
            tooltip: '重新连接'.tr,
            onPressed: () => mcp.reconnect(entry),
          ),
          IconButton(
            icon: const Icon(
              Icons.delete_outline,
              size: 16,
              color: AppColors.textSecondary,
            ),
            tooltip: '移除'.tr,
            onPressed: () => mcp.removeServer(entry),
          ),
        ],
      ),
    );
  }
}

/// 设置开关行
class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: value ? AppColors.accent : AppColors.textSecondary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: AppColors.accent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// API 地址展示行（含复制按钮）
class _AddressTile extends StatelessWidget {
  const _AddressTile({
    required this.url,
    required this.lanHint,
    required this.onCopy,
  });

  final String url;
  final String lanHint;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent),
      ),
      child: Row(
        children: [
          const Icon(Icons.link, size: 18, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  url,
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  lanHint,
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.copy_rounded,
              size: 16,
              color: AppColors.accent,
            ),
            tooltip: '复制地址'.tr,
            onPressed: onCopy,
          ),
        ],
      ),
    );
  }
}

/// 「对话」区块：Ask 提问开关
class _AskSection extends StatelessWidget {
  const _AskSection();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final ask = AskUserService.to;
      return Column(
        children: [
          _SwitchTile(
            icon: Icons.quiz_outlined,
            title: '允许模型向我提问',
            subtitle:
                '任务中缺少关键信息时，模型会弹出问卷请你选择；'
                '关闭后模型只能靠猜测推进',
            value: ask.enabled.value,
            onChanged: ask.setEnabled,
          ),
          const SizedBox(height: 8),
          const _HintText(
            'Ask 技能对齐 DeepSeek Harness 的人机问答机制：'
            '模型发出结构化问题（含选项、可多选），你提交答案后它继续任务；'
            '跳过提问会回喂 ASK_ABORTED，模型自行决定换路推进。',
          ),
        ],
      );
    });
  }
}

/// 「API 模型」区块：导入 OpenAI 兼容远程模型，与本地模型并存
class _ApiModelsSection extends StatelessWidget {
  const _ApiModelsSection();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final service = ApiModelService.to;
      final configs = service.configs;
      return Column(
        children: [
          _ActionTile(
            icon: Icons.cloud_upload_outlined,
            title: '导入 API 模型',
            subtitle: '填入 Base URL / API Key / 模型名（OpenAI 兼容接口）',
            loading: false,
            onTap: () => showConfigDialog(),
          ),
          for (final config in configs) ...[
            const SizedBox(height: 8),
            _ApiModelCard(config: config),
          ],
          if (configs.isNotEmpty) ...[
            const SizedBox(height: 8),
            const _HintText(
              'API 模型不走本地推理：对话、记忆、工具调用均在远程模型上生效，'
              '费用由你的 API 提供商计费；API Key 仅保存在本机。',
            ),
          ],
        ],
      );
    });
  }

  static Future<void> showConfigDialog({ApiModelConfig? existing}) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final baseUrl = TextEditingController(text: existing?.baseUrl ?? '');
    final apiKey = TextEditingController(text: existing?.apiKey ?? '');
    final model = TextEditingController(text: existing?.model ?? '');
    final formKey = GlobalKey<FormState>();

    await Get.dialog<void>(
      AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          existing == null ? '导入 API 模型' : '编辑 API 模型',
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(name, '名称（如 DeepSeek 官方）'),
              _field(
                baseUrl,
                'Base URL（如 https://api.deepseek.com）',
                validator: (v) => v == null || !v.startsWith('http')
                    ? '需以 http(s):// 开头'
                    : null,
              ),
              _field(apiKey, 'API Key（sk-…）', obscure: true),
              _field(
                model,
                '模型名（如 deepseek-chat）',
                validator: (v) => v == null || v.trim().isEmpty ? '必填' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back<void>(),
            child: const Text(
              '取消',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () async {
              if (formKey.currentState?.validate() != true) return;
              final service = ApiModelService.to;
              if (existing == null) {
                await service.add(
                  name: name.text,
                  baseUrl: baseUrl.text,
                  apiKey: apiKey.text,
                  model: model.text,
                );
              } else {
                existing
                  ..name = name.text.trim().isEmpty
                      ? existing.model
                      : name.text.trim()
                  ..baseUrl = baseUrl.text.trim()
                  ..apiKey = apiKey.text.trim()
                  ..model = model.text.trim();
                service.configs.refresh();
                await service.update(existing);
              }
              Get.back<void>();
            },
            child: const Text(
              '保存',
              style: TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _field(
    TextEditingController controller,
    String hint, {
    bool obscure = false,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        validator: validator,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(
            color: AppColors.textTertiary,
            fontSize: 12,
          ),
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

/// 单个 API 模型卡片：开始对话 / 编辑 / 删除
class _ApiModelCard extends StatelessWidget {
  const _ApiModelCard({required this.config});

  final ApiModelConfig config;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.cloud_outlined,
              size: 20,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ModelNameText(
                  config.name,
                  maxLines: 2,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                  ),
                ),
                ModelNameText(
                  '${config.model} · ${config.maskedKey}',
                  maxLines: 2,
                  tooltip: false,
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => Get.toNamed(
              AppRoutes.chat,
              arguments: <String, dynamic>{
                'apiModelId': config.id,
                'modelName': config.name,
              },
            ),
            child: const Text(
              '对话',
              style: TextStyle(
                color: AppColors.accent,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          PopupMenuButton<String>(
            color: AppColors.surfaceHigh,
            icon: const Icon(
              Icons.more_vert,
              size: 18,
              color: AppColors.textSecondary,
            ),
            onSelected: (value) async {
              if (value == 'edit') {
                await _ApiModelsSection.showConfigDialog(existing: config);
              } else if (value == 'delete') {
                await ApiModelService.to.remove(config.id);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'edit',
                child: Text(
                  '编辑',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text(
                  '删除',
                  style: TextStyle(color: AppColors.danger, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
