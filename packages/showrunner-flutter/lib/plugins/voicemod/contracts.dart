import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';

final class VoiceModEmptyConfig {
  const VoiceModEmptyConfig();

  factory VoiceModEmptyConfig.fromRuntime(RuntimeMap value) =>
      const VoiceModEmptyConfig();

  RuntimeMap toRuntime() => {};
}

final class VoiceModSelectVoiceConfig {
  const VoiceModSelectVoiceConfig({this.voice = ''});

  factory VoiceModSelectVoiceConfig.fromRuntime(RuntimeMap value) =>
      VoiceModSelectVoiceConfig(voice: value['voice']?.toString() ?? '');

  final String voice;

  RuntimeMap toRuntime() => {'voice': voice};
}

final class VoiceModConfigCodec<C> implements PluginConfigCodec<C> {
  const VoiceModConfigCodec(this._decoder, this._encoder);

  final C Function(RuntimeMap) _decoder;
  final RuntimeMap Function(C value) _encoder;

  @override
  C decode(RuntimeMap value) => _decoder(value);

  @override
  RuntimeMap encode(C value) => _encoder(value);
}

final voiceModEmptyConfigCodec = VoiceModConfigCodec(
  VoiceModEmptyConfig.fromRuntime,
  (VoiceModEmptyConfig value) => value.toRuntime(),
);
final voiceModSelectVoiceConfigCodec = VoiceModConfigCodec(
  VoiceModSelectVoiceConfig.fromRuntime,
  (VoiceModSelectVoiceConfig value) => value.toRuntime(),
);
