import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart' as ffi;

import '../models/work_device.dart';

/// 设备注册表（sqflite，应用级单例）
///
/// 与 ChatHistoryDatabase 同库不同表（复用 mota 数据库文件），
/// 桌面端走 sqflite_common_ffi，落盘应用支持目录。
class WorkRegistry {
  WorkRegistry._();

  static final WorkRegistry instance = WorkRegistry._();

  static const String _dbName = 'mota_chat_history.db';
  static const String _table = 'work_devices';
  static const int _version = 1;

  Database? _db;
  bool _factoryReady = false;

  void _ensureDesktopFactory() {
    if (_factoryReady) return;
    _factoryReady = true;
    if (kIsWeb) return;
    if (Platform.isWindows || Platform.isLinux) {
      ffi.sqfliteFfiInit();
      databaseFactory = ffi.databaseFactoryFfi;
    }
  }

  Future<String> _resolveDbPath() async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      final dir = await getApplicationSupportDirectory();
      return '${dir.path}${Platform.pathSeparator}$_dbName';
    }
    return _dbName;
  }

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
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            platform TEXT NOT NULL,
            endpoint TEXT NOT NULL,
            token TEXT NOT NULL,
            tier_id TEXT NOT NULL DEFAULT 'view_only',
            created_at INTEGER NOT NULL,
            last_seen_at INTEGER,
            device_model TEXT
          )
        ''');
      },
      onOpen: (db) async {
        // 老版本数据库无本表（mota 库先于 Work 模块存在）：惰性补齐
        await db.execute('''
          CREATE TABLE IF NOT EXISTS $_table (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            platform TEXT NOT NULL,
            endpoint TEXT NOT NULL,
            token TEXT NOT NULL,
            tier_id TEXT NOT NULL DEFAULT 'view_only',
            created_at INTEGER NOT NULL,
            last_seen_at INTEGER,
            device_model TEXT
          )
        ''');
      },
    );
    _db = db;
    return db;
  }

  /// 全部设备（按创建时间倒序）
  Future<List<WorkDevice>> listDevices() async {
    final db = await database;
    final rows = await db.query(_table, orderBy: 'created_at DESC');
    return rows.map(WorkDevice.fromJson).toList();
  }

  /// 插入或更新（按 id 主键冲突替换）
  Future<void> upsert(WorkDevice device) async {
    final db = await database;
    await db.insert(
      _table,
      <String, dynamic>{
        'id': device.id,
        'name': device.name,
        'platform': device.platform.id,
        'endpoint': device.endpoint,
        'token': device.token,
        'tier_id': device.tierId,
        'created_at': device.createdAt,
        'last_seen_at': device.lastSeenAt,
        'device_model': device.deviceModel,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    debugPrint('WorkRegistry: upsert ${device.name} (${device.endpoint})');
  }

  /// 更新探测状态（在线时间/型号）
  Future<void> touch(String id, {String? deviceModel}) async {
    final db = await database;
    await db.update(
      _table,
      <String, dynamic>{
        'last_seen_at': DateTime.now().millisecondsSinceEpoch,
        if (deviceModel != null) 'device_model': deviceModel,
      },
      where: 'id = ?',
      whereArgs: <Object>[id],
    );
  }

  /// 更新对端权限档位（控制端只能「请求」，实际档位以对端为准，
  /// 这里记录的是控制端视角的申请值，探测时会以对端 /work/status 为准校正）
  Future<void> setTier(String id, String tierId) async {
    final db = await database;
    await db.update(
      _table,
      <String, dynamic>{'tier_id': tierId},
      where: 'id = ?',
      whereArgs: <Object>[id],
    );
  }

  /// 删除设备（解绑）
  Future<void> remove(String id) async {
    final db = await database;
    await db.delete(_table, where: 'id = ?', whereArgs: <Object>[id]);
  }

  /// 按 endpoint 查找（配对去重：同一地址重复配对只更新令牌）
  Future<WorkDevice?> findByEndpoint(String endpoint) async {
    final db = await database;
    final rows = await db.query(
      _table,
      where: 'endpoint = ?',
      whereArgs: <Object>[endpoint],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return WorkDevice.fromJson(rows.first);
  }
}
