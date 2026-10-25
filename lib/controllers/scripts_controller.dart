import 'dart:convert';

import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/js_sandbox.dart';

/// 一个用户脚本（模型代码解释器之外的手动执行入口）
class JsScript {
  JsScript({
    required this.id,
    required this.name,
    required this.code,
    required this.createdAt,
    required this.updatedAt,
    this.lastRunAt,
    this.lastRunOk,
    this.lastRunSummary = '',
  });

  final String id;
  String name;
  String code;
  final DateTime createdAt;
  DateTime updatedAt;
  DateTime? lastRunAt;
  bool? lastRunOk;
  String lastRunSummary;

  JsScript copyWith({
    String? name,
    String? code,
    DateTime? updatedAt,
    DateTime? lastRunAt,
    bool? lastRunOk,
    String? lastRunSummary,
  }) {
    return JsScript(
      id: id,
      name: name ?? this.name,
      code: code ?? this.code,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastRunAt: lastRunAt ?? this.lastRunAt,
      lastRunOk: lastRunOk ?? this.lastRunOk,
      lastRunSummary: lastRunSummary ?? this.lastRunSummary,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'code': code,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'lastRunAt': lastRunAt?.millisecondsSinceEpoch,
    'lastRunOk': lastRunOk,
    'lastRunSummary': lastRunSummary,
  };

  static JsScript fromJson(Map<String, dynamic> json) => JsScript(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '未命名脚本',
    code: json['code'] as String? ?? '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (json['createdAt'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
    ),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      (json['updatedAt'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
    ),
    lastRunAt: json['lastRunAt'] is int
        ? DateTime.fromMillisecondsSinceEpoch(json['lastRunAt'] as int)
        : null,
    lastRunOk: json['lastRunOk'] as bool?,
    lastRunSummary: json['lastRunSummary'] as String? ?? '',
  );
}

/// 脚本管理：列表、持久化（shared_preferences）、运行（QuickJS 沙箱）
class ScriptsController extends GetxController {
  static const String _storageKey = 'js_scripts_v1';

  final scripts = <JsScript>[].obs;
  bool _loaded = false;

  /// 从本地存储加载（幂等，仅首次生效）
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      scripts.assignAll(
        decoded
            .whereType<Map>()
            .map((e) => JsScript.fromJson(e.cast<String, dynamic>()))
            .where((s) => s.id.isNotEmpty),
      );
    } catch (_) {
      // 存储损坏：忽略，按空列表处理
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(scripts.map((s) => s.toJson()).toList()),
    );
  }

  /// 新建脚本并返回（调用方持引用进入编辑）
  Future<JsScript> create({String name = '未命名脚本'}) async {
    await load();
    final now = DateTime.now();
    final script = JsScript(
      id: now.millisecondsSinceEpoch.toRadixString(36),
      name: name,
      code: '// 在这里编写 JavaScript\n'
          '// 可用 console.log 输出，支持数学计算与数据处理\n'
          'console.log("hello MOTA");\n'
          '1 + 1',
      createdAt: now,
      updatedAt: now,
    );
    scripts.insert(0, script);
    await _persist();
    return script;
  }

  /// 新建/更新一个脚本（按 id upsert）
  Future<void> save(JsScript script) async {
    await load();
    script.updatedAt = DateTime.now();
    final index = scripts.indexWhere((s) => s.id == script.id);
    if (index >= 0) {
      scripts[index] = script;
    } else {
      scripts.insert(0, script);
    }
    await _persist();
    scripts.refresh();
  }

  /// 删除脚本
  Future<void> delete(String id) async {
    scripts.removeWhere((s) => s.id == id);
    await _persist();
    scripts.refresh();
  }

  /// 在沙箱中执行脚本，返回结构化结果并记录最近运行状态
  Future<JsExecResult> run(JsScript script) async {
    final result = await JsSandboxService.instance.execute(script.code);
    script.lastRunAt = DateTime.now();
    script.lastRunOk = result.ok;
    script.lastRunSummary = result.summary.length > 300
        ? '${result.summary.substring(0, 300)}…'
        : result.summary;
    await _persist();
    scripts.refresh();
    return result;
  }
}
