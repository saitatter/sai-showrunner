import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';

final class SoundPlaybackConfig {
  const SoundPlaybackConfig({
    this.output,
    this.sound,
    this.volume,
    this.startTime,
    this.endTime,
    this.abortPlay,
    this.playId,
  });

  factory SoundPlaybackConfig.fromRuntime(RuntimeMap value) =>
      SoundPlaybackConfig(
        output: value['output'],
        sound: value['sound']?.toString() ?? value['file']?.toString(),
        volume: _asDouble(value['volume']),
        startTime: _asDouble(value['startTime']),
        endTime: _asDouble(value['endTime']),
        abortPlay: value['_abortPlay']?.toString(),
        playId: value['_playId']?.toString(),
      );

  final Object? output;
  final String? sound;
  final double? volume;
  final double? startTime;
  final double? endTime;
  final String? abortPlay;
  final String? playId;

  RuntimeMap toRuntime() => {
    if (output != null) 'output': output,
    if (sound != null) 'sound': sound,
    if (volume != null) 'volume': volume,
    if (startTime != null) 'startTime': startTime,
    if (endTime != null) 'endTime': endTime,
    if (abortPlay != null) '_abortPlay': abortPlay,
    if (playId != null) '_playId': playId,
  };
}

final class TtsActionConfig {
  const TtsActionConfig({
    this.text,
    this.output,
    this.voice,
    this.voiceProvider,
    this.voiceName,
    this.voiceLocale,
    this.providerConfig,
    this.volume,
    this.pitch,
    this.rate,
  });

  factory TtsActionConfig.fromRuntime(RuntimeMap value) => TtsActionConfig(
    text: value['text']?.toString(),
    output: value['output'],
    voice: value['voice'],
    voiceProvider: value['voiceProvider']?.toString(),
    voiceName: value['voiceName']?.toString(),
    voiceLocale: value['voiceLocale']?.toString(),
    providerConfig: value['providerConfig'] is Map
        ? Map<String, dynamic>.from(value['providerConfig'] as Map)
        : null,
    volume: _asDouble(value['volume']),
    pitch: _asDouble(value['pitch']),
    rate: _asDouble(value['rate']),
  );

  final String? text;
  final Object? output;
  final Object? voice;
  final String? voiceProvider;
  final String? voiceName;
  final String? voiceLocale;
  final RuntimeMap? providerConfig;
  final double? volume;
  final double? pitch;
  final double? rate;

  RuntimeMap toRuntime() => {
    if (text != null) 'text': text,
    if (output != null) 'output': output,
    if (voice != null) 'voice': voice,
    if (voiceProvider != null) 'voiceProvider': voiceProvider,
    if (voiceName != null) 'voiceName': voiceName,
    if (voiceLocale != null) 'voiceLocale': voiceLocale,
    if (providerConfig != null) 'providerConfig': providerConfig,
    if (volume != null) 'volume': volume,
    if (pitch != null) 'pitch': pitch,
    if (rate != null) 'rate': rate,
  };
}

final class SoundConfigCodec<C> implements PluginConfigCodec<C> {
  const SoundConfigCodec(this._decoder, this._encoder);

  final C Function(RuntimeMap) _decoder;
  final RuntimeMap Function(C value) _encoder;

  @override
  C decode(RuntimeMap value) => _decoder(value);

  @override
  RuntimeMap encode(C value) => _encoder(value);
}

final soundPlaybackConfigCodec = SoundConfigCodec(
  SoundPlaybackConfig.fromRuntime,
  (SoundPlaybackConfig value) => value.toRuntime(),
);
final ttsActionConfigCodec = SoundConfigCodec(
  TtsActionConfig.fromRuntime,
  (TtsActionConfig value) => value.toRuntime(),
);

double? _asDouble(Object? value) => switch (value) {
  num value => value.toDouble(),
  String value => double.tryParse(value),
  _ => null,
};
