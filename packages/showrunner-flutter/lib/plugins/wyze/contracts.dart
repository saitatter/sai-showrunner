import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';

enum WyzePowerMode { enabled, disabled, toggle }

WyzePowerMode wyzePowerModeFromRuntime(Object? value) {
  final normalized = value?.toString().toLowerCase();
  if (normalized == 'off' || normalized == 'false') {
    return WyzePowerMode.disabled;
  }
  if (normalized == 'toggle') return WyzePowerMode.toggle;
  return WyzePowerMode.enabled;
}

final class WyzeActionConfig {
  const WyzeActionConfig({
    this.email,
    this.password,
    this.device,
    this.model,
    this.power,
    this.color,
  });

  factory WyzeActionConfig.fromRuntime(RuntimeMap value) => WyzeActionConfig(
    email: value['email']?.toString(),
    password: value['password']?.toString(),
    device: value['device']?.toString(),
    model: value['model']?.toString(),
    power: value.containsKey('state')
        ? wyzePowerModeFromRuntime(value['state'])
        : null,
    color: value['color']?.toString(),
  );

  final String? email;
  final String? password;
  final String? device;
  final String? model;
  final WyzePowerMode? power;
  final String? color;

  RuntimeMap toRuntime() => {
    if (email != null) 'email': email,
    if (password != null) 'password': password,
    if (device != null) 'device': device,
    if (model != null) 'model': model,
    if (power != null)
      'state': switch (power!) {
        WyzePowerMode.enabled => 'on',
        WyzePowerMode.disabled => 'off',
        WyzePowerMode.toggle => 'toggle',
      },
    if (color != null) 'color': color,
  };
}

final class WyzeConfigCodec<C> implements PluginConfigCodec<C> {
  const WyzeConfigCodec(this._decoder, this._encoder);

  final C Function(RuntimeMap) _decoder;
  final RuntimeMap Function(C value) _encoder;

  @override
  C decode(RuntimeMap value) => _decoder(value);

  @override
  RuntimeMap encode(C value) => _encoder(value);
}

final wyzeActionConfigCodec = WyzeConfigCodec(
  WyzeActionConfig.fromRuntime,
  (WyzeActionConfig value) => value.toRuntime(),
);
