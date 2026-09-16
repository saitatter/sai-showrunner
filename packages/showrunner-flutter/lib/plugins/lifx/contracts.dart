import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';

enum LifxPowerMode { enabled, disabled, toggle }

LifxPowerMode lifxPowerModeFromRuntime(Object? value) {
  final normalized = value?.toString().toLowerCase();
  if (normalized == 'off' || normalized == 'false') {
    return LifxPowerMode.disabled;
  }
  if (normalized == 'toggle') return LifxPowerMode.toggle;
  return LifxPowerMode.enabled;
}

final class LifxLightConfig {
  const LifxLightConfig({
    this.power,
    this.host,
    this.port,
    this.target,
    this.color,
    this.transitionSeconds,
  });

  factory LifxLightConfig.fromRuntime(RuntimeMap value) => LifxLightConfig(
    power: value.containsKey('state')
        ? lifxPowerModeFromRuntime(value['state'])
        : null,
    host: value['host']?.toString(),
    port: _asInt(value['port']),
    target: value['target']?.toString(),
    color: value['color']?.toString(),
    transitionSeconds: _asDouble(value['transition']),
  );

  final LifxPowerMode? power;
  final String? host;
  final int? port;
  final String? target;
  final String? color;
  final double? transitionSeconds;

  RuntimeMap toRuntime() => {
    if (power != null)
      'state': switch (power!) {
        LifxPowerMode.enabled => 'on',
        LifxPowerMode.disabled => 'off',
        LifxPowerMode.toggle => 'toggle',
      },
    if (host != null) 'host': host,
    if (port != null) 'port': port,
    if (target != null) 'target': target,
    if (color != null) 'color': color,
    if (transitionSeconds != null) 'transition': transitionSeconds,
  };
}

final class LifxConfigCodec<C> implements PluginConfigCodec<C> {
  const LifxConfigCodec(this._decoder, this._encoder);

  final C Function(RuntimeMap) _decoder;
  final RuntimeMap Function(C value) _encoder;

  @override
  C decode(RuntimeMap value) => _decoder(value);

  @override
  RuntimeMap encode(C value) => _encoder(value);
}

final lifxLightConfigCodec = LifxConfigCodec(
  LifxLightConfig.fromRuntime,
  (LifxLightConfig value) => value.toRuntime(),
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
