import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';

final class AdvssMessageConfig {
  const AdvssMessageConfig({this.message = ''});

  factory AdvssMessageConfig.fromRuntime(RuntimeMap value) =>
      AdvssMessageConfig(message: value['message']?.toString() ?? '');

  final String message;

  RuntimeMap toRuntime() => {'message': message};
}

final class AdvssEventConfig {
  const AdvssEventConfig({this.message});

  factory AdvssEventConfig.fromRuntime(RuntimeMap value) =>
      AdvssEventConfig(message: value['message']?.toString());

  final String? message;

  RuntimeMap toRuntime() => {if (message != null) 'message': message};
}

final class AdvssEvent {
  const AdvssEvent({
    required this.vendorName,
    required this.eventType,
    this.message,
    this.payload = const {},
  });

  factory AdvssEvent.fromRuntime(RuntimeMap value) => AdvssEvent(
    vendorName: value['vendorName']?.toString() ?? '',
    eventType: value['eventType']?.toString() ?? '',
    message: value['message']?.toString(),
    payload: Map<String, dynamic>.from(value),
  );

  final String vendorName;
  final String eventType;
  final String? message;
  final RuntimeMap payload;

  RuntimeMap toRuntime() => Map<String, dynamic>.from(payload);
}

final class AdvssConfigCodec<C> implements PluginConfigCodec<C> {
  const AdvssConfigCodec(this._decoder, this._encoder);

  final C Function(RuntimeMap) _decoder;
  final RuntimeMap Function(C value) _encoder;

  @override
  C decode(RuntimeMap value) => _decoder(value);

  @override
  RuntimeMap encode(C value) => _encoder(value);
}

final advssMessageConfigCodec = AdvssConfigCodec(
  AdvssMessageConfig.fromRuntime,
  (AdvssMessageConfig value) => value.toRuntime(),
);

final advssEventConfigCodec = AdvssConfigCodec(
  AdvssEventConfig.fromRuntime,
  (AdvssEventConfig value) => value.toRuntime(),
);
