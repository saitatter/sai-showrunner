import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';

final class IotActionConfig {
  const IotActionConfig({
    this.lightId,
    this.light,
    this.plug,
    this.plugId,
    this.state,
    this.on,
    this.switchState,
    this.lightColor,
    this.color,
    this.transition,
  });

  factory IotActionConfig.fromRuntime(RuntimeMap value) => IotActionConfig(
    lightId: value['lightId'],
    light: value['light'],
    plug: value['plug'],
    plugId: value['plugId'],
    state: value['state'],
    on: value['on'],
    switchState: value['switch'],
    lightColor: value['lightColor'],
    color: value['color'],
    transition: value['transition'],
  );

  final Object? lightId;
  final Object? light;
  final Object? plug;
  final Object? plugId;
  final Object? state;
  final Object? on;
  final Object? switchState;
  final Object? lightColor;
  final Object? color;
  final Object? transition;

  RuntimeMap toRuntime() => {
    if (lightId != null) 'lightId': lightId,
    if (light != null) 'light': light,
    if (plug != null) 'plug': plug,
    if (plugId != null) 'plugId': plugId,
    if (state != null) 'state': state,
    if (on != null) 'on': on,
    if (switchState != null) 'switch': switchState,
    if (lightColor != null) 'lightColor': lightColor,
    if (color != null) 'color': color,
    if (transition != null) 'transition': transition,
  };
}

final class IotConfigCodec<C> implements PluginConfigCodec<C> {
  const IotConfigCodec(this._decoder, this._encoder);

  final C Function(RuntimeMap) _decoder;
  final RuntimeMap Function(C value) _encoder;

  @override
  C decode(RuntimeMap value) => _decoder(value);

  @override
  RuntimeMap encode(C value) => _encoder(value);
}

final iotActionConfigCodec = IotConfigCodec(
  IotActionConfig.fromRuntime,
  (IotActionConfig value) => value.toRuntime(),
);
