import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';

enum ElgatoPowerMode { enabled, disabled, toggle }

ElgatoPowerMode elgatoPowerModeFromRuntime(Object? value) {
  final normalized = value?.toString().toLowerCase();
  if (normalized == 'off' || normalized == 'false') {
    return ElgatoPowerMode.disabled;
  }
  if (normalized == 'toggle') return ElgatoPowerMode.toggle;
  return ElgatoPowerMode.enabled;
}

final class ElgatoEmptyConfig {
  const ElgatoEmptyConfig();

  factory ElgatoEmptyConfig.fromRuntime(RuntimeMap value) =>
      const ElgatoEmptyConfig();

  RuntimeMap toRuntime() => {};
}

final class ElgatoLightStateConfig {
  const ElgatoLightStateConfig({
    this.power = ElgatoPowerMode.enabled,
    this.host,
    this.port = 9123,
    this.color,
    this.numberOfLights,
  });

  factory ElgatoLightStateConfig.fromRuntime(RuntimeMap value) =>
      ElgatoLightStateConfig(
        power: elgatoPowerModeFromRuntime(value['state']),
        host: value['host']?.toString().trim(),
        port: _asInt(value['port']) ?? 9123,
        color: value['color']?.toString(),
        numberOfLights: value.containsKey('numberOfLights')
            ? _positiveInt(value['numberOfLights'], 1)
            : null,
      );

  final ElgatoPowerMode power;
  final String? host;
  final int port;
  final String? color;
  final int? numberOfLights;

  RuntimeMap toRuntime() => {
    'state': switch (power) {
      ElgatoPowerMode.enabled => 'on',
      ElgatoPowerMode.disabled => 'off',
      ElgatoPowerMode.toggle => 'toggle',
    },
    if (host != null) 'host': host,
    'port': port,
    if (color != null) 'color': color,
    if (numberOfLights != null) 'numberOfLights': numberOfLights,
  };
}

final class ElgatoConfigCodec<C> implements PluginConfigCodec<C> {
  const ElgatoConfigCodec(this._decoder, this._encoder);

  final C Function(RuntimeMap) _decoder;
  final RuntimeMap Function(C value) _encoder;

  @override
  C decode(RuntimeMap value) => _decoder(value);

  @override
  RuntimeMap encode(C value) => _encoder(value);
}

final elgatoEmptyConfigCodec = ElgatoConfigCodec(
  ElgatoEmptyConfig.fromRuntime,
  (ElgatoEmptyConfig value) => value.toRuntime(),
);
final elgatoLightStateConfigCodec = ElgatoConfigCodec(
  ElgatoLightStateConfig.fromRuntime,
  (ElgatoLightStateConfig value) => value.toRuntime(),
);

int? _asInt(Object? value) => switch (value) {
  int value => value,
  num value => value.toInt(),
  String value => int.tryParse(value),
  _ => null,
};

int _positiveInt(Object? value, int fallback) {
  final number = _asInt(value);
  return number != null && number > 0 ? number : fallback;
}
