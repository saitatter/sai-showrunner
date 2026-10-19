import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';

enum GoveePowerMode { enabled, disabled, toggle }

GoveePowerMode goveePowerModeFromRuntime(Object? value) {
  final normalized = value?.toString().toLowerCase();
  if (normalized == 'off' || normalized == 'false') {
    return GoveePowerMode.disabled;
  }
  if (normalized == 'toggle') return GoveePowerMode.toggle;
  return GoveePowerMode.enabled;
}

final class GoveeDeviceConfig {
  const GoveeDeviceConfig({
    this.device,
    this.model,
    this.power,
    this.color,
    this.brightness,
  });

  factory GoveeDeviceConfig.fromRuntime(RuntimeMap value) => GoveeDeviceConfig(
    device: value['device']?.toString(),
    model: value['model']?.toString(),
    power: value.containsKey('state')
        ? goveePowerModeFromRuntime(value['state'])
        : null,
    color: value['color']?.toString(),
    brightness: _asDouble(value['brightness']),
  );

  final String? device;
  final String? model;
  final GoveePowerMode? power;
  final String? color;
  final double? brightness;

  RuntimeMap toRuntime() => {
    if (device != null) 'device': device,
    if (model != null) 'model': model,
    if (power != null)
      'state': switch (power!) {
        GoveePowerMode.enabled => 'on',
        GoveePowerMode.disabled => 'off',
        GoveePowerMode.toggle => 'toggle',
      },
    if (color != null) 'color': color,
    if (brightness != null) 'brightness': brightness,
  };
}

final class GoveeConfigCodec<C> implements PluginConfigCodec<C> {
  const GoveeConfigCodec(this._decoder, this._encoder);

  final C Function(RuntimeMap) _decoder;
  final RuntimeMap Function(C value) _encoder;

  @override
  C decode(RuntimeMap value) => _decoder(value);

  @override
  RuntimeMap encode(C value) => _encoder(value);
}

final goveeDeviceConfigCodec = GoveeConfigCodec(
  GoveeDeviceConfig.fromRuntime,
  (GoveeDeviceConfig value) => value.toRuntime(),
);

double? _asDouble(Object? value) => switch (value) {
  num value => value.toDouble(),
  String value => double.tryParse(value),
  _ => null,
};
