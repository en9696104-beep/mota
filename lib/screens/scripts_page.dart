import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/scripts_controller.dart';
import '../routes/app_routes.dart';
import '../theme/app_theme.dart';

/// JS 脚本管理页：列表、新建、进入编辑/运行
class ScriptsPage extends StatefulWidget {
  const ScriptsPage({super.key});

  @override
  State<ScriptsPage> createState() => _ScriptsPageState();
}

class _ScriptsPageState extends State<ScriptsPage> {
  final ScriptsController _controller = Get.find<ScriptsController>();

  @override
  void initState() {
    super.initState();
    _controller.load();
  }

  Future<void> _createScript() async {
    final script = await _controller.create();
    await Get.toNamed(AppRoutes.scriptEditor, arguments: script);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('JS 脚本')),
      body: Obx(() {
        if (_controller.scripts.isEmpty) {
          return _EmptyState(onCreate: _createScript);
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: _controller.scripts.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final script = _controller.scripts[index];
            return _ScriptCard(
              script: script,
              onTap: () => Get.toNamed(
                AppRoutes.scriptEditor,
                arguments: script,
              ),
            );
          },
        );
      }),
      floatingActionButton: FloatingActionButton(
        onPressed: _createScript,
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.black,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});

  final Future<void> Function() onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.code_outlined,
              size: 48,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 16),
            const Text(
              '还没有脚本\n点击右下角按钮创建第一个 JavaScript 脚本',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 13,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onCreate,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                side: const BorderSide(color: AppColors.accent),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新建脚本'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScriptCard extends StatelessWidget {
  const _ScriptCard({required this.script, required this.onTap});

  final JsScript script;
  final VoidCallback onTap;

  /// 相对时间格式化：刚刚 / N 分钟前 / N 小时前 / N 天前 / M/D
  static String _formatTime(DateTime? time) {
    if (time == null) return '';
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 30) return '${diff.inDays} 天前';
    return '${time.month}/${time.day}';
  }

  @override
  Widget build(BuildContext context) {
    final preview = script.code
        .split('\n')
        .where((line) => line.trim().isNotEmpty && !line.trim().startsWith('//'))
        .take(2)
        .join(' ');
    final lastRun = script.lastRunAt == null
        ? null
        : '上次运行：${script.lastRunOk == true ? '成功' : '失败'}'
              ' · ${_formatTime(script.lastRunAt)}';
    return GestureDetector(
      onTap: onTap,
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
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: switch (script.lastRunOk) {
                  true => AppColors.accent,
                  false => AppColors.danger,
                  null => AppColors.textTertiary,
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    script.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    preview.isEmpty ? '（空脚本）' : preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      '更新于 ${_formatTime(script.updatedAt)}',
                      if (lastRun != null) lastRun,
                    ].join('　'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 10.5,
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
}
