import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../services/memory_service.dart';
import '../services/model_repository.dart';
import '../theme/app_theme.dart';

/// 记忆管理页：条目列表 / 手动添加 / 编辑 / 删除。
///
/// 作用域语义对齐 RikkaHub：
/// - 全局记忆池：所有开启 useGlobalMemory 的模型共享
/// - 模型私有：每个模型独立的记忆存储
class MemoryPage extends StatefulWidget {
  const MemoryPage({super.key});

  @override
  State<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends State<MemoryPage> {
  MemoryService get _memory => MemoryService.to;

  /// 当前查看的作用域
  String _scope = memoryScopeGlobal;

  List<MemoryEntry> _entries = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // 默认展示当前设置对应的作用域
    _scope = _memory.settings.value.useGlobalMemory
        ? memoryScopeGlobal
        : (Get.arguments is String ? Get.arguments as String : memoryScopeGlobal);
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final entries = await _memory.entriesFor(_scope);
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  Future<void> _addEntry() => _editDialog(null);

  Future<void> _editEntry(MemoryEntry entry) => _editDialog(entry);

  Future<void> _editDialog(MemoryEntry? entry) async {
    final controller = TextEditingController(text: entry?.content ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          entry == null ? '添加记忆' : '编辑记忆',
          style: const TextStyle(
              color: AppColors.textPrimary, fontSize: 16),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          style: const TextStyle(
              color: AppColors.textPrimary, fontSize: 13, height: 1.5),
          decoration: const InputDecoration(
            hintText: '例如：用户偏好使用 Dart 开发，项目名 MOTA',
            hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 12),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('保存',
                style: TextStyle(
                    color: AppColors.accent, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final text = controller.text.trim();
    if (text.isEmpty) return;
    if (entry == null) {
      await _memory.addEntry(_scope, text);
    } else {
      entry.content = text;
      await _memory.updateEntry(entry);
    }
    _reload();
  }

  Future<void> _deleteEntry(MemoryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('删除记忆',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: const Text(
          '删除后模型在后续对话中将不再记得该信息。',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _memory.deleteEntry(entry.id);
    _reload();
  }

  Future<void> _clearScope() async {
    if (_entries.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('清空全部记忆',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: Text(
          '将删除当前作用域的全部 ${_entries.length} 条记忆，不可恢复。',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _memory.clearScope(_scope);
    _reload();
  }

  /// 作用域切换（全局 / 模型私有）
  Future<void> _pickScope() async {
    // 收集已有记忆的模型作用域
    final scopes = <String>[memoryScopeGlobal, ..._modelScopes];
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: AppColors.surface,
        title: const Text('选择记忆作用域',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 15)),
        children: scopes
            .map((s) => SimpleDialogOption(
                  onPressed: () => Navigator.of(ctx).pop(s),
                  child: Text(
                    _scopeLabel(s),
                    style: TextStyle(
                      color: s == _scope ? AppColors.accent : AppColors.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                ))
            .toList(),
      ),
    );
    if (selected == null || selected == _scope) return;
    setState(() => _scope = selected);
    _reload();
  }

  /// 数据库中出现过的模型私有作用域（延迟初始化缓存）
  List<String> _modelScopes = const [];
  bool _scopesLoaded = false;

  Future<void> _ensureScopes() async {
    if (_scopesLoaded) return;
    _scopesLoaded = true;
    // 从全部条目聚合作用域（简单实现：查全局 + 逐模型成本低，直接查全局表）
    // 这里复用 entriesFor(global) 无法覆盖，故用独立查询
    final dbScopes = await _memory.knownModelScopes();
    if (!mounted) return;
    setState(() => _modelScopes = dbScopes);
  }

  String _scopeLabel(String scope) {
    if (scope == memoryScopeGlobal) return '全局记忆池';
    final model = ModelRepository.to.byId(scope);
    return model?.name ?? '模型 $scope';
  }

  @override
  Widget build(BuildContext context) {
    _ensureScopes();
    return Scaffold(
      appBar: AppBar(
        title: const Text('记忆管理', style: TextStyle(fontSize: 17)),
        actions: [
          if (_entries.isNotEmpty)
            IconButton(
              tooltip: '清空当前作用域',
              icon: const Icon(Icons.delete_sweep_outlined, size: 20),
              onPressed: _clearScope,
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.black,
        onPressed: _addEntry,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          // 作用域切换条
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: InkWell(
              onTap: _pickScope,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.folder_special_outlined,
                        size: 16, color: AppColors.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _scopeLabel(_scope),
                        style: const TextStyle(
                            color: AppColors.textPrimary, fontSize: 13),
                      ),
                    ),
                    const Icon(Icons.swap_horiz,
                        size: 16, color: AppColors.textTertiary),
                  ],
                ),
              ),
            ),
          ),
          const _HintBar(),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(strokeWidth: 2))
                : _entries.isEmpty
                    ? const _EmptyView()
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                        itemCount: _entries.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, index) {
                          final entry = _entries[index];
                          return _EntryCard(
                            entry: entry,
                            onEdit: () => _editEntry(entry),
                            onDelete: () => _deleteEntry(entry),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

/// 记忆条目卡片
class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    required this.onEdit,
    required this.onDelete,
  });

  final MemoryEntry entry;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final time = DateTime.fromMillisecondsSinceEpoch(entry.updatedAt);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.lightbulb_outline,
                size: 16, color: AppColors.accent),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.content,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 4),
                Text(
                  '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                      color: AppColors.textTertiary, fontSize: 10),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.edit_outlined, size: 16),
            color: AppColors.textSecondary,
            onPressed: onEdit,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.delete_outline, size: 16),
            color: AppColors.textTertiary,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _HintBar extends StatelessWidget {
  const _HintBar();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 12, color: AppColors.textTertiary),
          SizedBox(width: 4),
          Expanded(
            child: Text(
              '开启记忆后，快速模型会在每轮对话后自动提取值得记住的信息；也可在此手动添加。',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 10),
            ),
          ),
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
          Icon(Icons.psychology_outlined, size: 44,
              color: AppColors.textTertiary),
          SizedBox(height: 10),
          Text(
            '这里还没有记忆',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
          SizedBox(height: 4),
          Text(
            '开启记忆后对话将被自动提取，或点右下角手动添加',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
