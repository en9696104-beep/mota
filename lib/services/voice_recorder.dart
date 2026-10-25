import 'dart:io';

import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

/// 语音录音服务（合作系统 ASR 输入）：麦克风 → WAV 文件。
///
/// 固定 16kHz 单声道 WAV（Qwen3-ASR 推荐的编码格式），
/// 录音文件写入系统临时目录，识别完成后由调用方清理。
class VoiceRecorderService {
  VoiceRecorderService._();

  static final VoiceRecorderService instance = VoiceRecorderService._();

  final AudioRecorder _recorder = AudioRecorder();

  bool _recording = false;

  /// 是否正在录音
  bool get isRecording => _recording;

  /// 请求权限并开始录音；成功返回录音文件路径，失败/无权限返回 null。
  Future<String?> start() async {
    if (_recording) return null;
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) return null;
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/mota_voice_${DateTime.now().millisecondsSinceEpoch}.wav';
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 256000,
        ),
        path: path,
      );
      _recording = true;
      return path;
    } catch (_) {
      return null;
    }
  }

  /// 停止录音，返回录音文件路径（未在录音时返回 null）
  Future<String?> stop() async {
    if (!_recording) return null;
    _recording = false;
    try {
      return await _recorder.stop();
    } catch (_) {
      return null;
    }
  }

  /// 取消录音（丢弃文件）
  Future<void> cancel() async {
    if (!_recording) return;
    _recording = false;
    try {
      final path = await _recorder.stop();
      if (path != null) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    } catch (_) {}
  }

  Future<void> dispose() => _recorder.dispose();
}
