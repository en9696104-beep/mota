import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 设备端离线 OCR（Google ML Kit，移动端专用）。
///
/// 背景：llama_flutter_android 0.2.6 的 ChatMessage 仅支持纯文本，
/// 移动端视觉模型（mmproj 投影器）无法加载，「用视觉模型做 OCR」在
/// Android 上不可行。ML Kit 的文字识别模型随 APK 离线捆绑（含中文包），
/// 不依赖 Google Play 服务、不需要联网，为移动端提供真正可用的 OCR 通道。
///
/// 桌面端（llamadart 支持图像输入）不走本服务，由视觉模型完成 OCR。
class OcrService {
  OcrService._();
  static final OcrService instance = OcrService._();

  TextRecognizer? _recognizer;

  /// 当前平台是否支持设备端 OCR（ML Kit 仅移动端可用）
  static bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// 识别图片中的文字（保持版面行结构拼接）。
  ///
  /// 失败返回 null，由调用方回退或给出提示。
  Future<String?> recognizeFile(String path) async {
    if (!isSupported) return null;
    try {
      final inputImage = InputImage.fromFilePath(path);
      final recognizer = _ensureRecognizer();
      final result = await recognizer.processImage(inputImage);
      final text = result.text.trim();
      return text.isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  TextRecognizer _ensureRecognizer() {
    // 中文包已随 APK 捆绑（build.gradle 引入 text-recognition-chinese），
    // 直接用中文识别器：对拉丁字符同样生效
    return _recognizer ??=
        TextRecognizer(script: TextRecognitionScript.chinese);
  }

  /// 释放底层识别器（App 生命周期内常驻，仅测试或极端场景调用）
  Future<void> dispose() async {
    try {
      await _recognizer?.close();
    } catch (_) {}
    _recognizer = null;
  }
}

/// OCR 结果缓存（LRU + 3 天过期，对齐 RikkaHub 的 OCR 缓存策略）。
///
/// 键 = 图片内容哈希 + OCR 提示词哈希；同一张图片三天内重复发送
/// 直接复用转录文本，不重复调用识别。
class OcrCache {
  OcrCache._();

  static const String _prefsKey = 'ocr_cache_v1';
  static const Duration ttl = Duration(days: 3);
  static const int maxEntries = 64;

  /// 计算缓存键：图片字节哈希 + 提示词哈希
  static String cacheKey(String imagePath, String prompt) {
    final bytes = File(imagePath).readAsBytesSync();
    final promptHash = md5.convert(utf8.encode(prompt)).toString();
    return '${md5.convert(bytes).toString()}:$promptHash';
  }

  /// 读取缓存；命中返回转录文本，未命中 / 过期 / 损坏返回 null
  static Future<String?> get(String imagePath, String prompt) async =>
      getByKey(cacheKey(imagePath, prompt));

  /// 按显式键读取（测试用）
  static Future<String?> getByKey(String key) async {
    if (key.isEmpty) return null;
    final entries = await _loadEntries();
    final entry = entries[key];
    if (entry is! Map<String, dynamic>) return null;
    final ts = entry['ts'];
    final text = entry['text'];
    if (ts is! int || text is! String) return null;
    if (DateTime.now().millisecondsSinceEpoch - ts > ttl.inMilliseconds) {
      return null;
    }
    return text;
  }

  /// 写入缓存（写入前清理过期条目；超容量时淘汰最旧条目）
  static Future<void> put(String imagePath, String prompt, String text) =>
      putByKey(cacheKey(imagePath, prompt), text);

  /// 按显式键写入（测试用）
  static Future<void> putByKey(String key, String text) async {
    if (key.isEmpty || text.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final entries = await _loadEntries();
    final now = DateTime.now().millisecondsSinceEpoch;

    entries.removeWhere(
      (_, v) =>
          v is! Map<String, dynamic> ||
          v['ts'] is! int ||
          now - (v['ts'] as int) > ttl.inMilliseconds,
    );
    entries[key] = {'text': text, 'ts': now};

    while (entries.length > maxEntries) {
      String? oldestKey;
      int? oldestTs;
      entries.forEach((k, v) {
        final ts = v['ts'];
        if (ts is int && (oldestTs == null || ts < oldestTs!)) {
          oldestTs = ts;
          oldestKey = k;
        }
      });
      if (oldestKey == null) break;
      entries.remove(oldestKey);
    }

    await prefs.setString(_prefsKey, jsonEncode(entries));
  }

  /// 清空缓存（测试 / 用户清理存储）
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  static Future<Map<String, dynamic>> _loadEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return <String, dynamic>{};
  }
}
