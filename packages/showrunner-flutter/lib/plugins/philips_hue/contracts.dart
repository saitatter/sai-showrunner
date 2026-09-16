import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';

enum HuePowerMode { enabled, disabled, toggle }

HuePowerMode huePowerModeFromRuntime(Object? value) {
  final normalized = value?.toString().toLowerCase();
  if (normalized == 'off' || normalized == 'false') {
    return HuePowerMode.disabled;
  }
  if (normalized == 'toggle') return HuePowerMode.toggle;
  return HuePowerMode.enabled;
}

final class HueActionConfig {
  const HueActionConfig({
    this.lightId,
    this.host,
    this.hubKey,
    this.resourceType,
    this.power,
    this.color,
    this.transitionSeconds,
    this.group,
    this.sceneId,
    this.scene,
  });

  factory HueActionConfig.fromRuntime(RuntimeMap value) => HueActionConfig(
    lightId: value['lightId']?.toString(),
    host: value['host']?.toString(),
    hubKey: value['hubKey']?.toString(),
    resourceType: value['resourceType']?.toString(),
    power: value.containsKey('state')
        ? huePowerModeFromRuntime(value['state'])
        : null,
    color: value['color']?.toString(),
    transitionSeconds: _asDouble(value['transition']),
    group: value['group'],
    sceneId: value['sceneId']?.toString(),
    scene: value['scene']?.toString(),
  );

  final String? lightId;
  final String? host;
  final String? hubKey;
  final String? resourceType;
  final HuePowerMode? power;
  final String? color;
  final double? transitionSeconds;
  final Object? group;
  final String? sceneId;
  final String? scene;

  RuntimeMap toRuntime() => {
    if (lightId != null) 'lightId': lightId,
    if (host != null) 'host': host,
    if (hubKey != null) 'hubKey': hubKey,
    if (resourceType != null) 'resourceType': resourceType,
    if (power != null)
      'state': switch (power!) {
        HuePowerMode.enabled => 'on',
        HuePowerMode.disabled => 'off',
        HuePowerMode.toggle => 'toggle',
      },
    if (color != null) 'color': color,
    if (transitionSeconds != null) 'transition': transitionSeconds,
    if (group != null) 'group': group,
    if (sceneId != null) 'sceneId': sceneId,
    if (scene != null) 'scene': scene,
  };
}

final class HueConfigCodec<C> implements PluginConfigCodec<C> {
  const HueConfigCodec(this._decoder, this._encoder);

  final C Function(RuntimeMap) _decoder;
  final RuntimeMap Function(C value) _encoder;

  @override
  C decode(RuntimeMap value) => _decoder(value);

  @override
  RuntimeMap encode(C value) => _encoder(value);
}

final hueActionConfigCodec = HueConfigCodec(
  HueActionConfig.fromRuntime,
  (HueActionConfig value) => value.toRuntime(),
);

double? _asDouble(Object? value) => switch (value) {
  num value => value.toDouble(),
  String value => double.tryParse(value),
  _ => null,
};
