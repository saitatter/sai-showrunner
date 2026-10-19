import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';

enum KasaPowerMode { enabled, disabled, toggle }

KasaPowerMode kasaPowerModeFromRuntime(Object? value) {
  final normalized = value?.toString().toLowerCase();
  if (normalized == 'off' || normalized == 'false') {
    return KasaPowerMode.disabled;
  }
  if (normalized == 'toggle') return KasaPowerMode.toggle;
  return KasaPowerMode.enabled;
}

final class KasaDeviceConfig {
  const KasaDeviceConfig({
    this.power,
    this.host,
    this.port,
    this.color,
    this.transitionSeconds,
  });

  factory KasaDeviceConfig.fromRuntime(RuntimeMap value) => KasaDeviceConfig(
    power: value.containsKey('state')
        ? kasaPowerModeFromRuntime(value['state'])
        : null,
    host: value['host']?.toString(),
    port: _asInt(value['port']),
    color: value['color']?.toString(),
    transitionSeconds: _asDouble(value['transition']),
  );

  final KasaPowerMode? power;
  final String? host;
  final int? port;
  final String? color;
  final double? transitionSeconds;

  RuntimeMap toRuntime() => {
    if (power != null)
      'state': switch (power!) {
        KasaPowerMode.enabled => 'on',
        KasaPowerMode.disabled => 'off',
        KasaPowerMode.toggle => 'toggle',
      },
    if (host != null) 'host': host,
    if (port != null) 'port': port,
    if (color != null) 'color': color,
    if (transitionSeconds != null) 'transition': transitionSeconds,
  };
}

final class KasaConfigCodec<C> implements PluginConfigCodec<C> {
  const KasaConfigCodec(this._decoder, this._encoder);

  final C Function(RuntimeMap) _decoder;
  final RuntimeMap Function(C value) _encoder;

  @override
  C decode(RuntimeMap value) => _decoder(value);

  @override
  RuntimeMap encode(C value) => _encoder(value);
}

final kasaDeviceConfigCodec = KasaConfigCodec(
  KasaDeviceConfig.fromRuntime,
  (KasaDeviceConfig value) => value.toRuntime(),
);

int? _asInt(Object? value) => switch (value) {
  int value => value,
  num value => value.toInt(),
  String value => int.tryParse(value),
  _ => null,
};

double? _asDouble(Object? value) => switch (value) {
  num value => value.toDouble(),
  String value => double.tryParse(value),
  _ => null,
};
