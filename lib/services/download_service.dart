import 'dart:io';

import 'package:dio/dio.dart';

import 'storage_service.dart';

/// 模型下载服务（单例）
///
/// - 从 GGUF 直链（hf-mirror.com 等）下载到 <app documents>/models/<id>.gguf
/// - 先写 .tmp 临时文件，完成后 rename，保证不会出现"半个文件"被当成已下载
/// - 支持进度回调与取消
class DownloadService {
  DownloadService._();

  static final DownloadService instance = DownloadService._();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 30),
    ),
  );

  final _cancelTokens = <String, CancelToken>{};

  bool isDownloading(String id) => _cancelTokens.containsKey(id);

  /// 下载一个模型。成功返回 true，失败抛异常，取消返回 false。
  ///
  /// [projectorUrl] 非空时，主模型下载完成后再下载多模态投影器
  /// （OCR / ASR / TTS 类模型必需），存为 `<id>.mmproj.gguf`。
  Future<bool> download({
    required String id,
    required String url,
    void Function(double progress)? onProgress,
    String? projectorUrl,
  }) async {
    if (_cancelTokens.containsKey(id)) return false;

    final savePath = await StorageService.to.localPathFor(id);
    final tmpPath = '$savePath.tmp';
    final cancelToken = CancelToken();
    _cancelTokens[id] = cancelToken;

    try {
      await _dio.download(
        url,
        tmpPath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          // 有投影器时：主文件占 90% 进度，投影器占 10%
          final factor = projectorUrl == null || projectorUrl.isEmpty
              ? 1.0
              : 0.9;
          if (total > 0) {
            onProgress?.call(received / total * factor);
          }
        },
      );

      // 完整性兜底：空文件视为失败
      final tmpFile = File(tmpPath);
      if (!await tmpFile.exists() || await tmpFile.length() == 0) {
        throw Exception('下载文件为空');
      }

      // 原子完成
      await tmpFile.rename(savePath);
      await StorageService.to.markDownloaded(id, savePath);

      // 投影器（多模态模型配套，缺失则模型不可用）
      if (projectorUrl != null && projectorUrl.isNotEmpty) {
        onProgress?.call(0.9);
        final projectorPath = await StorageService.to.localProjectorPathFor(id);
        await _dio.download(
          projectorUrl,
          '$projectorPath.tmp',
          cancelToken: cancelToken,
          onReceiveProgress: (received, total) {
            if (total > 0) {
              onProgress?.call(0.9 + received / total * 0.1);
            }
          },
        );
        final projectorTmp = File('$projectorPath.tmp');
        if (!await projectorTmp.exists() || await projectorTmp.length() == 0) {
          throw Exception('投影器文件为空');
        }
        await projectorTmp.rename(projectorPath);
        onProgress?.call(1.0);
      }
      return true;
    } catch (e) {
      // 清理残留的临时文件
      final tmpFile = File(tmpPath);
      if (await tmpFile.exists()) {
        await tmpFile.delete();
      }
      rethrow;
    } finally {
      _cancelTokens.remove(id);
    }
  }

  /// 取消下载
  void cancel(String id) {
    _cancelTokens[id]?.cancel('用户取消了下载');
  }

  /// 删除本地模型文件与下载记录（含投影器文件）
  Future<void> delete(String id) async {
    final path = await StorageService.to.localPathFor(id);
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
    final projectorPath = await StorageService.to.localProjectorPathFor(id);
    final projectorFile = File(projectorPath);
    if (await projectorFile.exists()) {
      await projectorFile.delete();
    }
    await StorageService.to.removeDownload(id);
  }
}
