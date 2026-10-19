import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';

final class BlueskyPostConfig {
  const BlueskyPostConfig({
    this.account,
    this.identifier,
    this.appPassword,
    this.text,
  });

  factory BlueskyPostConfig.fromRuntime(RuntimeMap value) => BlueskyPostConfig(
    account: value['account'],
    identifier: value['identifier']?.toString(),
    appPassword: value['appPassword']?.toString(),
    text: value['text']?.toString(),
  );

  final Object? account;
  final String? identifier;
  final String? appPassword;
  final String? text;

  RuntimeMap toRuntime() => {
    if (account != null) 'account': account,
    if (identifier != null) 'identifier': identifier,
    if (appPassword != null) 'appPassword': appPassword,
    if (text != null) 'text': text,
  };
}

final class BlueskyConfigCodec<C> implements PluginConfigCodec<C> {
  const BlueskyConfigCodec(this._decoder, this._encoder);

  final C Function(RuntimeMap) _decoder;
  final RuntimeMap Function(C value) _encoder;

  @override
  C decode(RuntimeMap value) => _decoder(value);

  @override
  RuntimeMap encode(C value) => _encoder(value);
}

final blueskyPostConfigCodec = BlueskyConfigCodec(
  BlueskyPostConfig.fromRuntime,
  (BlueskyPostConfig value) => value.toRuntime(),
);
