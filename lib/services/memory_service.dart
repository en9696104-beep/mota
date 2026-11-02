import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import 'dart:io' show Platform;

import '../data/models/ai_model.dart';
import 'chat_history_db.dart';
import 'llama_service.dart';
import 'model_repository.dart';
import 'storage_service.dart';

/// 记忆作用域：全局共享池，或按模型（助手）私有隔离。
/// 对齐 RikkaHub 的 useGlobalMemory 语义。
const String memoryScopeGlobal = 'global';

/// 单条记忆条目。
class MemoryEntry {
  MemoryEntry({
    required this.id,
    required this.scope,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;

  /// 所属作用域：'global' 或模型 id
  final String scope;

  /// 记忆内容（一句话）
  String content;

  final int createdAt;
  final int updatedAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'scope': scope,
        'content': content,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  static MemoryEntry fromMap(Map<String, dynamic> map) => MemoryEntry(
        id: map['id'] as int,
        scope: map['scope'] as String,
        content: map['content'] as String,
        createdAt: map['created_at'] as int,
        updatedAt: map['updated_at'] as int,
      );
}

/// 记忆系统设置（shared_preferences 持久化）。
///
/// 参数命名对齐 RikkaHub 文档：
/// - [enabled]：enableMemory，主开关
/// - [useGlobalMemory]：useGlobalMemory，全局共享池 vs 模型私有
/// - [enableRecentChats]：enableRecentChatsReference，最近对话引用
/// - [enableTimeReminder]：enableTimeReminder，时间间隔提醒
/// - [extractionModelId]：记忆提取用的快速模型（低成本小模型）
class MemorySettings {
  MemorySettings({
    this.enabled = false,
    this.useGlobalMemory = false,
    this.enableRecentChats = false,
    this.enableTimeReminder = false,
    this.extractionModelId,
  });

  bool enabled;
  bool useGlobalMemory;
  bool enableRecentChats;
  bool enableTimeReminder;

  /// 记忆提取模型 id；null 时自动选用最小的已下载对话模型
  String? extractionModelId;

  static const String _prefsKey = 'memory_settings_v1';

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'useGlobalMemory': useGlobalMemory,
        'enableRecentChats': enableRecentChats,
        'enableTimeReminder': enableTimeReminder,
        'extractionModelId': extractionModelId,
      };

  static MemorySettings fromJson(Map<String, dynamic> json) => MemorySettings(
        enabled: json['enabled'] as bool? ?? false,
        useGlobalMemory: json['useGlobalMemory'] as bool? ?? false,
        enableRecentChats: json['enableRecentChats'] as bool? ?? false,
        enableTimeReminder: json['enableTimeReminder'] as bool? ?? false,
        extractionModelId: json['extractionModelId'] as String?,
      );

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(toJson()));
  }

  static Future<MemorySettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return MemorySettings();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return MemorySettings.fromJson(decoded);
    } catch (_) {}
    return MemorySettings();
  }
}

/// 记忆系统（对齐 RikkaHub 类 ChatGPT 智能记忆机制）：
///
/// - **提取**：对话结束后，由快速模型（低成本小模型）监控并提取值得
///   记住的信息（用户偏好、决策、背景），作为独立条目存入数据库
/// - **注入**：新对话开始前，相关条目注入 system prompt，让模型带着
///   记忆起步，无需每次重复自我介绍
/// - **隔离**：默认每个模型私有记忆；开启 [MemorySettings.useGlobalMemory]
///   后读写共享的全局记忆池
/// - **条目管理**：可随时查看、添加、编辑、删除
class MemoryService extends GetxService {
  static MemoryService get to => Get.find<MemoryService>();

  final settings = MemorySettings().obs;

  /// 数据库就绪标志（失败时记忆功能静默降级，不影响对话）
  bool dbReady = false;

  Database? _db;

  Future<MemoryService> init() async {
    settings.value = await MemorySettings.load();
    try {
      _db = await _openDatabase();
      dbReady = true;
    } catch (e) {
      debugPrint('MemoryDB 初始化失败（记忆功能降级）: $e');
    }
    return this;
  }

  // ---------- 存储层（sqflite，独立于聊天记录库） ----------

  Future<Database> _openDatabase() async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      ffi.sqfliteFfiInit();
      databaseFactory = ffi.databaseFactoryFfi;
      final dir = await getApplicationSupportDirectory();
      return openDatabase(
        '${dir.path}${Platform.pathSeparator}mota_memory.db',
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE memories (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              scope TEXT NOT NULL,
              content TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
          await db.execute(
            'CREATE INDEX idx_memories_scope ON memories (scope, updated_at DESC)',
          );
        },
      );
    }
    return openDatabase(
      'mota_memory.db',
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE memories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            scope TEXT NOT NULL,
            content TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_memories_scope ON memories (scope, updated_at DESC)',
        );
      },
    );
  }

  /// 更新设置（UI 层调用）
  Future<void> updateSettings(MemorySettings next) async {
    settings.value = next;
    await next.save();
  }

  // ---------- 条目 CRUD ----------

  /// 指定作用域的全部条目（按更新时间倒序）
  Future<List<MemoryEntry>> entriesFor(String scope) async {
    final db = _db;
    if (db == null) return const [];
    try {
      final rows = await db.query(
        'memories',
        where: 'scope = ?',
        whereArgs: <Object?>[scope],
        orderBy: 'updated_at DESC',
      );
      return rows.map(MemoryEntry.fromMap).toList();
    } catch (_) {
      return const [];
    }
  }

  /// 新增条目；内容为空返回 null
  Future<MemoryEntry?> addEntry(String scope, String content) async {
    final text = content.trim();
    if (text.isEmpty || _db == null) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await _db!.insert('memories', {
      'scope': scope,
      'content': text,
      'created_at': now,
      'updated_at': now,
    });
    return MemoryEntry(
      id: id,
      scope: scope,
      content: text,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// 编辑条目内容
  Future<void> updateEntry(MemoryEntry entry) async {
    final db = _db;
    if (db == null) return;
    await db.update(
      'memories',
      {
        'content': entry.content.trim(),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[entry.id],
    );
  }

  /// 删除条目
  Future<void> deleteEntry(int id) async {
    final db = _db;
    if (db == null) return;
    await db.delete('memories', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  /// 清空某作用域的全部记忆
  Future<void> clearScope(String scope) async {
    final db = _db;
    if (db == null) return;
    await db.delete('memories', where: 'scope = ?', whereArgs: <Object?>[scope]);
  }

  /// 已有记忆的模型私有作用域列表（记忆管理页作用域切换用，不含 global）
  Future<List<String>> knownModelScopes() async {
    final db = _db;
    if (db == null) return const [];
    try {
      final rows = await db.rawQuery(
        "SELECT DISTINCT scope FROM memories WHERE scope != ?",
        <Object?>[memoryScopeGlobal],
      );
      return rows
          .map((r) => r['scope'])
          .whereType<String>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// 当前设置下，某模型对话应读写的记忆作用域
  String scopeFor(String modelId) =>
      settings.value.useGlobalMemory ? memoryScopeGlobal : modelId;

  // ---------- 注入 ----------

  /// 生成注入 system prompt 的记忆块；无需注入时返回 null。
  ///
  /// 组成（各自可开关）：
  /// 1. 记忆条目列表（主开关）
  /// 2. 时间提醒：距上次对话过去了多久（enableTimeReminder）
  /// 3. 最近对话主题引用（enableRecentChats）
  Future<String?> buildMemoryPrompt(String modelId) async {
    if (!settings.value.enabled || modelId.isEmpty) return null;
    final parts = <String>[];

    // 1. 记忆条目
    final entries = await entriesFor(scopeFor(modelId));
    if (entries.isNotEmpty) {
      final buffer = StringBuffer('关于用户的已知记忆（回答时可自然参考）：');
      for (final e in entries.take(50)) {
        buffer.write('\n- ${e.content}');
      }
      parts.add(buffer.toString());
    }

    // 2. 时间提醒
    if (settings.value.enableTimeReminder) {
      final last = await ChatHistoryDatabase.instance.lastTurnTimeFor(modelId);
      if (last != null) {
        final gap = DateTime.now().difference(last);
        parts.add('距上次对话已过去 ${describeGap(gap)}。');
      }
    }

    // 3. 最近对话引用（更广泛的连续性，而非离散条目）
    if (settings.value.enableRecentChats) {
      final turns =
          await ChatHistoryDatabase.instance.turnsForModel(modelId);
      if (turns.length > 1) {
        final recent = turns.reversed.take(5);
        final topics = recent
            .map((t) => t.userContent.trim())
            .where((s) => s.isNotEmpty)
            .map((s) => s.length > 40 ? '${s.substring(0, 40)}…' : s)
            .join('；');
        if (topics.isNotEmpty) {
          parts.add('最近几轮对话主题：$topics');
        }
      }
    }

    if (parts.isEmpty) return null;
    return '<memory>\n${parts.join('\n')}\n</memory>';
  }

  /// 时间间隔的人性化描述
  static String describeGap(Duration gap) {
    if (gap.inDays >= 1) return '${gap.inDays} 天';
    if (gap.inHours >= 1) return '${gap.inHours} 小时';
    return '${gap.inMinutes.clamp(1, 59)} 分钟';
  }

  // ---------- 提取 ----------

  /// 从一轮完成的对话中提取记忆（后台异步执行，不阻塞 UI）。
  ///
  /// 流程：快速模型生成 JSON 数组 → 去重（与已有条目相同/包含关系）→ 入库。
  Future<void> extractFromTurn({
    required String modelId,
    required String userText,
    required String assistantText,
  }) async {
    if (!settings.value.enabled || !dbReady) return;
    if (userText.trim().isEmpty || assistantText.trim().isEmpty) return;
    final scope = scopeFor(modelId);

    final quickModel = await _resolveQuickModel();
    if (quickModel == null) return;

    final buffer = StringBuffer();
    try {
      final loaded = await LlamaService.instance.loadModel(
        quickModel.path,
        threads: 2,
        contextSize: 2048,
      );
      if (!loaded) return;
      try {
        await for (final chunk in LlamaService.instance.generateChatStream(
          [
            const LlamaTurn(role: 'system', content: 'You are a memory extractor. Output JSON only.'),
            LlamaTurn(
              role: 'user',
              content: _extractionPrompt(userText, assistantText),
            ),
          ],
          temperature: 0.1,
          maxTokens: 256,
        )) {
          buffer.write(chunk);
        }
      } finally {
        await LlamaService.instance.dispose();
      }
    } catch (e) {
      debugPrint('记忆提取失败: $e');
      return;
    }

    final facts = parseFacts(buffer.toString());
    if (facts.isEmpty) return;

    // 去重：与已有条目完全相同或互相包含的跳过
    final existing = await entriesFor(scope);
    final existingTexts = existing.map((e) => e.content).toList();
    for (final fact in facts) {
      final text = fact.trim();
      if (text.isEmpty || text.length > 120) continue;
      final dup = existingTexts.any((t) =>
          t == text || t.contains(text) || text.contains(t));
      if (dup) continue;
      final entry = await addEntry(scope, text);
      if (entry != null) existingTexts.add(entry.content);
    }
  }

  /// 解析快速模型输出中的记忆数组（容忍代码块包裹 / 前后缀文本）
  static List<String> parseFacts(String output) {
    var text = output.trim();
    // 剥离 ```json ... ``` 包裹
    final codeBlock = RegExp(r'```(?:json)?\s*(.*?)```', dotAll: true);
    final match = codeBlock.firstMatch(text);
    if (match != null) text = match.group(1)!.trim();
    // 截取最外层 JSON 数组
    final start = text.indexOf('[');
    final end = text.lastIndexOf(']');
    if (start < 0 || end <= start) return const [];
    try {
      final decoded = jsonDecode(text.substring(start, end + 1));
      if (decoded is List) {
        return decoded.whereType<String>().toList();
      }
    } catch (_) {}
    return const [];
  }

  static String _extractionPrompt(String userText, String assistantText) {
    final user = userText.length > 500 ? userText.substring(0, 500) : userText;
    final assistant =
        assistantText.length > 500 ? assistantText.substring(0, 500) : assistantText;
    return '分析下面的对话，提取值得跨对话长期记住的用户信息'
        '（用户偏好、背景事实、进行中的项目、明确表达的长期需求）。\n'
        '要求：\n'
        '- 只提取持久信息，不要提取一次性任务细节或寒暄\n'
        '- 每条一句话，不超过 50 字\n'
        '- 没有值得记住的信息时输出 []\n'
        '- 只输出 JSON 字符串数组，不要输出任何其他文字\n\n'
        '对话：\n用户：$user\n助手：$assistant';
  }

  /// 解析快速模型：优先用户配置；否则自动选已下载的最小对话模型
  Future<({AiModel model, String path, String? projectorPath})?>
      _resolveQuickModel() async {
    final configuredId = settings.value.extractionModelId;
    if (configuredId != null) {
      final model = ModelRepository.to.byId(configuredId);
      final path = StorageService.to.pathFor(configuredId);
      if (model != null && path != null) {
        return (model: model, path: path, projectorPath: null);
      }
    }
    // 自动兜底：已下载的对话模型按体积升序，取最小（加载快、推理便宜）
    final candidates = ModelRepository.to.models
        .where((m) => StorageService.to.pathFor(m.id) != null)
        .where((m) => m.hasCapability(ModelCapability.chat))
        .toList()
      ..sort((a, b) => a.sizeInGB.compareTo(b.sizeInGB));
    if (candidates.isEmpty) return null;
    final model = candidates.first;
    final path = StorageService.to.pathFor(model.id);
    if (path == null) return null;
    return (model: model, path: path, projectorPath: null);
  }

  /// 已下载的可作为提取模型的候选（设置页选择器用）
  List<AiModel> downloadedChatModels() => ModelRepository.to.models
      .where((m) => StorageService.to.pathFor(m.id) != null)
      .where((m) => m.hasCapability(ModelCapability.chat))
      .toList();
}
