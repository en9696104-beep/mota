import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

import 'inference/tts_audio.dart';

/// TTS 播放服务：PCM → 16-bit WAV 文件 → audioplayers 播放。
///
/// Qwen3-TTS 输出 float32 PCM（24kHz 单声道），先落地为 WAV 再播放，
/// 避免在内存中维护音频流水线。
class TtsPlayerService {
  TtsPlayerService._();

  static final TtsPlayerService instance = TtsPlayerService._();

  final AudioPlayer _player = AudioPlayer();

  bool _playing = false;

  /// 是否正在播放
  bool get isPlaying => _playing;

  /// 合成并播放一段 TTS 音频；返回生成的 WAV 路径（失败返回 null）。
  Future<String?> play(TtsAudio audio) async {
    if (audio.samples.isEmpty) return null;
    final path = await writeWav(audio);
    try {
      await _player.play(DeviceFileSource(path));
      _playing = true;
      _player.onPlayerComplete.listen((_) => _playing = false);
      return path;
    } catch (_) {
      return null;
    }
  }

  /// 停止播放
  Future<void> stop() async {
    _playing = false;
    try {
      await _player.stop();
    } catch (_) {}
  }

  Future<void> dispose() => _player.dispose();

  /// 把 float32 PCM 写成 16-bit PCM WAV，返回文件路径
  Future<String> writeWav(TtsAudio audio) async {
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/mota_tts_${DateTime.now().millisecondsSinceEpoch}.wav';
    final channels = audio.channelCount <= 0 ? 1 : audio.channelCount;
    final sampleRate = audio.sampleRateHz <= 0 ? 24000 : audio.sampleRateHz;

    final dataBytes = audio.samples.length * 2;
    final buffer = Uint8List(44 + dataBytes);
    final view = ByteData.view(buffer.buffer);

    void writeAscii(int offset, String text) {
      for (var i = 0; i < text.length; i++) {
        view.setUint8(offset + i, text.codeUnitAt(i));
      }
    }

    writeAscii(0, 'RIFF');
    view.setUint32(4, 36 + dataBytes, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    view.setUint32(16, 16, Endian.little); // fmt chunk size
    view.setUint16(20, 1, Endian.little); // PCM
    view.setUint16(22, channels, Endian.little);
    view.setUint32(24, sampleRate, Endian.little);
    view.setUint32(28, sampleRate * channels * 2, Endian.little); // byte rate
    view.setUint16(32, channels * 2, Endian.little); // block align
    view.setUint16(34, 16, Endian.little); // bits per sample
    writeAscii(36, 'data');
    view.setUint32(40, dataBytes, Endian.little);

    for (var i = 0; i < audio.samples.length; i++) {
      final sample = audio.samples[i];
      final clamped = sample < -1.0
          ? -1.0
          : (sample > 1.0 ? 1.0 : sample);
      view.setInt16(44 + i * 2, (clamped * 32767).round(), Endian.little);
    }

    await File(path).writeAsBytes(buffer);
    return path;
  }
}
