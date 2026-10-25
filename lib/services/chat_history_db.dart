import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import '../data/models/chat_turn.dart';

/// 聊天记录本地数据库（sqflite，应用级单例）
///
/// - 表 `chat_turns`：以「轮次」为粒度持久化（模型ID、时间戳、User内容、Assistant内容）
/// - 历史对话 Tab 按时间倒序聚合渲染；进入对话时按模型读取全量轮次恢复上下文
class ChatHistoryDatabase {
  ChatHistoryDatabase._();

  static final ChatHistoryDatabase instance = ChatHistoryDatabase._();

  static const String _dbName = 'mota_chat_history.db';
  static const String _table = 'chat_turns';
  static const int _version = 1;

  Database? _db;
  bool _factoryReady = false;

  /// 桌面端（Windows / Linux）sqflite 官方包无原生实现，
  /// 需注入 sqflite_common_ffi 工厂（SQLite C API 的 FFI 绑定）。
  /// macOS 由 sqflite_darwin 原生支持，无需注入；Android / iOS 走官方实现。
  void _ensureDesktopFactory() {
    if (_factoryReady) return;
    _factoryReady = true;
    if (kIsWeb) return;
    if (Platform.isWindows || Platform.isLinux) {
      ffi.sqfliteFfiInit();
      databaseFactory = ffi.databaseFactoryFfi;
      debugPrint('ChatHistoryDB: 桌面端已启用 sqflite_common_ffi 工厂');
    }
  }

  /// 桌面端数据库落盘到应用支持目录（FFI 工厂默认写在 .dart_tool 下，
  /// 不适合发布版：安装目录可能只读，且会被误清）。
  Future<String> _resolveDbPath() async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      final dir = await getApplicationSupportDirectory();
      return '${dir.path}${Platform.pathSeparator}$_dbName';
    }
    return _dbName; // Android / iOS / macOS：官方 sqflite 自行解析
  }

  /// 打开（或创建）数据库；重复调用直接复用
  Future<Database> get database async {
    final existing = _db;
    if (existing != null) return existing;
    _ensureDesktopFactory();
    final db = await openDatabase(
      await _resolveDbPath(),
      version: _version,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_table (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            model_id TEXT NOT NULL,
            model_name TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            user_content TEXT NOT NULL,
            assistant_content TEXT NOT NULL
          )
        ''');
        // 历史列表按模型 + 时间倒序查询
        await db.execute(
          'CREATE INDEX idx_turns_model_time ON $_table (model_id, created_at DESC)',
        );
      },
    );
    _db = db;
    return db;
  }

  /// 写入一轮对话（发送 + 接收完成后调用）
  Future<int> insertTurn(ChatTurn turn) async {
    final db = await database;
    return db.insert(_table, turn.toMap());
  }

  /// 某个模型的全部轮次（按时间正序，用于恢复上下文）
  Future<List<ChatTurn>> turnsForModel(String modelId) async {
    final db = await database;
    final rows = await db.query(
      _table,
      where: 'model_id = ?',
      whereArgs: <Object?>[modelId],
      orderBy: 'created_at ASC',
    );
    return rows.map(ChatTurn.fromMap).toList();
  }

  /// 全部轮次（按时间倒序，历史列表聚合用）
  Future<List<ChatTurn>> allTurnsDesc() async {
    final db = await database;
    final rows = await db.query(_table, orderBy: 'created_at DESC');
    return rows.map(ChatTurn.fromMap).toList();
  }

  /// 删除某个模型的全部轮次（历史列表左滑删除）
  Future<void> deleteTurnsForModel(String modelId) async {
    final db = await database;
    await db.delete(_table, where: 'model_id = ?', whereArgs: <Object?>[modelId]);
  }

  /// 删除单条轮次
  Future<void> deleteTurn(int id) async {
    final db = await database;
    await db.delete(_table, where: 'id = ?', whereArgs: <Object?>[id]);
  }

  /// 启动期安全初始化：数据库异常（如磁盘不可写）只降级历史功能，不阻塞启动
  Future<void> ensureInitialized() async {
    try {
      await database;
    } catch (e, s) {
      debugPrint('ChatHistoryDB 初始化失败（历史记录功能降级）: $e\n$s');
    }
  }
}
