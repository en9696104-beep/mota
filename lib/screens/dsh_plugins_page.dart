import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../services/dsh/dsh_models.dart';
import '../services/dsh/dsh_plugin_service.dart';
import '../theme/app_theme.dart';

/// DSH 插件管理页：安装（本地目录 / zip / GitHub）+ 启停 + 移除 + 工具清单。
class DshPluginsPage extends StatelessWidget {
  const DshPluginsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final service = Get.find<DshPluginService>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('DSH 插件', style: TextStyle(fontSize: 17)),
      ),
      floatingActionButton: Obx(
        () => FloatingActionButton.extended(
          backgroundColor:
              service.installing.value ? AppColors.textTertiary : AppColors.accent,
          foregroundColor: Colors.black,
          onPressed: service.installing.value ? null : () => _installSheet(context),
          icon: service.installing.value
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.add),
          label: Text(service.installing.value ? '安装中…' : '安装插件'),
        ),
      ),
      body: Obx(() {
        final plugins = service.plugins;
        if (plugins.isEmpty) {
          return const _EmptyView();
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
          itemCount: plugins.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, index) =>
              _PluginCard(service: service, plugin: plugins[index]),
        );
      }),
    );
  }

  void _installSheet(BuildContext context) {
    showModalBottomSheet(
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
              padding: EdgeInsets.all(14),
              child: Text(
                '安装 DSH 插件',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open_outlined,
                  color: AppColors.accent),
              title: const Text('本地目录',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              subtitle: const Text('选择包含 package.json 的插件目录',
                  style: TextStyle(color: AppColors.textTertiary, fontSize: 11)),
              onTap: () async {
                Get.back();
                final path = await FilePicker.getDirectoryPath();
                if (path == null) return;
                await _install(
                  () => Get.find<DshPluginService>().installFromDirectory(path),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.archive_outlined,
                  color: AppColors.accent),
              title: const Text('本地 zip 包',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              subtitle: const Text('选择插件 zip 归档',
                  style: TextStyle(color: AppColors.textTertiary, fontSize: 11)),
              onTap: () async {
                Get.back();
                final result = await FilePicker.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['zip'],
                );
                final path = result?.paths.whereType<String>().firstOrNull;
                if (path == null) return;
                await _install(
                  () => Get.find<DshPluginService>().installFromZip(path),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud_download_outlined,
                  color: AppColors.accent),
              title: const Text('GitHub 仓库',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              subtitle: const Text('例如 github:owner/repo',
                  style: TextStyle(color: AppColors.textTertiary, fontSize: 11)),
                onTap: () async {
                  Get.back();
                  final controller = TextEditingController();
                  final value = await Get.dialog<String>(
                    AlertDialog(
                      backgroundColor: AppColors.surface,
                      title: const Text('从 GitHub 安装',
                          style: TextStyle(
                              color: AppColors.textPrimary, fontSize: 16)),
                      content: TextField(
                        controller: controller,
                        autofocus: true,
                        style: const TextStyle(
                            color: AppColors.textPrimary, fontSize: 14),
                        decoration: const InputDecoration(
                          hintText: 'github:owner/repo',
                          hintStyle: TextStyle(color: AppColors.textTertiary),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Get.back(),
                          child: const Text('取消',
                              style:
                                  TextStyle(color: AppColors.textSecondary)),
                        ),
                        TextButton(
                          onPressed: () =>
                              Get.back(result: controller.text.trim()),
                          child: const Text('安装',
                              style: TextStyle(
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  );
                  if (value == null || value.isEmpty) return;
                  await _install(
                    () => Get.find<DshPluginService>().installFromGithub(value),
                  );
                },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  static Future<void> _install(Future<DshPlugin> Function() action) async {
    try {
      final plugin = await action();
      Get.snackbar(
        '插件安装成功',
        '${plugin.packageName} v${plugin.version}，注册了 ${plugin.tools.length} 个工具',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar('插件安装失败', e.toString(),
          snackPosition: SnackPosition.BOTTOM, duration: const Duration(seconds: 5));
    }
  }
}

/// 单个插件卡片
class _PluginCard extends StatelessWidget {
  const _PluginCard({required this.service, required this.plugin});

  final DshPluginService service;
  final DshPlugin plugin;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.extension_outlined,
                  size: 20,
                  color: plugin.enabled ? AppColors.accent : AppColors.textTertiary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${plugin.packageName} v${plugin.version}',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'id: ${plugin.id} · ${plugin.tools.length} 个工具',
                      style: const TextStyle(
                          color: AppColors.textTertiary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Switch(
                value: plugin.enabled,
                activeThumbColor: AppColors.accent,
                onChanged: (v) async {
                  try {
                    await service.setEnabled(plugin, v);
                  } catch (e) {
                    Get.snackbar('插件启用失败', e.toString(),
                        snackPosition: SnackPosition.BOTTOM);
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: AppColors.textSecondary),
                tooltip: '移除',
                onPressed: () async {
                  final confirmed = await Get.dialog<bool>(
                    AlertDialog(
                      backgroundColor: AppColors.surface,
                      title: const Text('移除插件',
                          style: TextStyle(
                              color: AppColors.textPrimary, fontSize: 16)),
                      content: Text(
                        '将删除 ${plugin.packageName} 及其 ${plugin.tools.length} 个工具。',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 13),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Get.back(result: false),
                          child: const Text('取消',
                              style:
                                  TextStyle(color: AppColors.textSecondary)),
                        ),
                        TextButton(
                          onPressed: () => Get.back(result: true),
                          child: const Text('移除',
                              style: TextStyle(color: AppColors.danger)),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) await service.remove(plugin);
                },
              ),
            ],
          ),
          if (plugin.tools.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final tool in plugin.tools)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 3),
                      child: Icon(Icons.build_outlined,
                          size: 12, color: AppColors.textTertiary),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${tool.name}：${tool.description.isEmpty ? "（无描述）" : tool.description}',
                        style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                            height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.extension_off_outlined, size: 44,
              color: AppColors.textTertiary),
          SizedBox(height: 10),
          Text(
            '还没有安装插件',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
          SizedBox(height: 4),
          Text(
            '支持 DeepSeek Harness 插件格式\n（本地目录 / zip / GitHub 仓库）',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textTertiary, fontSize: 11, height: 1.6),
          ),
        ],
      ),
    );
  }
}
