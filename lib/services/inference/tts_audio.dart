/// TTS 合成结果（PCM 音频，调用方负责写 WAV / 播放）
class TtsAudio {
  const TtsAudio({
    required this.samples,
    required this.sampleRateHz,
    required this.channelCount,
  });

  /// 交织的 float32 PCM 采样（-1.0 ~ 1.0）
  final List<double> samples;

  /// 采样率（Hz），Qwen3-TTS 为 24000
  final int sampleRateHz;

  /// 声道数（Qwen3-TTS 为 1）
  final int channelCount;

  /// 估算时长（秒）
  double get durationSeconds =>
      sampleRateHz <= 0 ? 0 : samples.length / (sampleRateHz * channelCount);
}
