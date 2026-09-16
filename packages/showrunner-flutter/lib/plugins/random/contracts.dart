import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';

final class RandomRangeConfig {
  const RandomRangeConfig({this.min = 0, this.max = 100});

  factory RandomRangeConfig.fromRuntime(RuntimeMap value) => RandomRangeConfig(
    min: _number(value['min'], 0),
    max: _number(value['max'], 100),
  );

  final num min;
  final num max;

  RuntimeMap toRuntime() => {'min': min, 'max': max};
}

final class RandomWheelTarget {
  const RandomWheelTarget({this.overlayId, this.widgetId});

  factory RandomWheelTarget.fromRuntime(Object? value) {
    if (value is! Map) return const RandomWheelTarget();
    return RandomWheelTarget(
      overlayId: _string(value['overlayId']),
      widgetId: _string(value['widgetId']),
    );
  }

  final String? overlayId;
  final String? widgetId;

  RuntimeMap toRuntime() => {
    if (overlayId != null) 'overlayId': overlayId,
    if (widgetId != null) 'widgetId': widgetId,
  };

  bool get isValid =>
      overlayId?.trim().isNotEmpty == true &&
      widgetId?.trim().isNotEmpty == true;
}

final class RandomWheelConfig {
  const RandomWheelConfig({this.wheel, this.strength = 1});

  factory RandomWheelConfig.fromRuntime(RuntimeMap value) => RandomWheelConfig(
    wheel: value.containsKey('wheel')
        ? RandomWheelTarget.fromRuntime(value['wheel'])
        : null,
    strength: _number(value['strength'], 1),
  );

  final RandomWheelTarget? wheel;
  final num strength;

  RuntimeMap toRuntime() => {
    if (wheel != null) 'wheel': wheel!.toRuntime(),
    'strength': strength,
  };
}

final class RandomWheelTriggerConfig {
  const RandomWheelTriggerConfig({required this.wheel, this.item});

  factory RandomWheelTriggerConfig.fromRuntime(RuntimeMap value) =>
      RandomWheelTriggerConfig(
        wheel: RandomWheelTarget.fromRuntime(value['wheel']),
        item: _string(value['item']),
      );

  final RandomWheelTarget wheel;
  final String? item;

  RuntimeMap toRuntime() => {
    'wheel': wheel.toRuntime(),
    if (item != null) 'item': item,
  };
}

final class RandomWheelLandedEvent {
  const RandomWheelLandedEvent({required this.wheel, this.item});

  factory RandomWheelLandedEvent.fromRuntime(RuntimeMap value) =>
      RandomWheelLandedEvent(
        wheel: RandomWheelTarget.fromRuntime(value['wheel']),
        item: _string(value['item']),
      );

  final RandomWheelTarget wheel;
  final String? item;

  RuntimeMap toRuntime() => {
    'wheel': wheel.toRuntime(),
    if (item != null) 'item': item,
  };
}

final class RandomConfigCodec<C> implements PluginConfigCodec<C> {
  const RandomConfigCodec(this._decoder, this._encoder);

  final C Function(RuntimeMap) _decoder;
  final RuntimeMap Function(C value) _encoder;

  @override
  C decode(RuntimeMap value) => _decoder(value);

  @override
  RuntimeMap encode(C value) => _encoder(value);
}

final randomRangeConfigCodec = RandomConfigCodec(
  RandomRangeConfig.fromRuntime,
  (RandomRangeConfig value) => value.toRuntime(),
);
final randomWheelConfigCodec = RandomConfigCodec(
  RandomWheelConfig.fromRuntime,
  (RandomWheelConfig value) => value.toRuntime(),
);
final randomWheelTriggerConfigCodec = RandomConfigCodec(
  RandomWheelTriggerConfig.fromRuntime,
  (RandomWheelTriggerConfig value) => value.toRuntime(),
);

String? _string(Object? value) => value?.toString();

num _number(Object? value, num fallback) =>
    value is num ? value : num.tryParse('$value') ?? fallback;
