import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';

final class RemoteButtonTriggerConfig {
  const RemoteButtonTriggerConfig({this.name});

  factory RemoteButtonTriggerConfig.fromRuntime(RuntimeMap value) =>
      RemoteButtonTriggerConfig(name: value['name']?.toString());

  final String? name;

  RuntimeMap toRuntime() => {if (name != null) 'name': name};
}

final class RemoteConfigCodec<C> implements PluginConfigCodec<C> {
  const RemoteConfigCodec(this._decoder, this._encoder);

  final C Function(RuntimeMap) _decoder;
  final RuntimeMap Function(C value) _encoder;

  @override
  C decode(RuntimeMap value) => _decoder(value);

  @override
  RuntimeMap encode(C value) => _encoder(value);
}

final remoteButtonTriggerConfigCodec = RemoteConfigCodec(
  RemoteButtonTriggerConfig.fromRuntime,
  (RemoteButtonTriggerConfig value) => value.toRuntime(),
);
