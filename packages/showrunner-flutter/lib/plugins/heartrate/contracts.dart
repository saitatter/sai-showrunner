import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';

final class HeartRateEmptyConfig {
  const HeartRateEmptyConfig();

  RuntimeMap toRuntime() => const {};
}

final class HeartRateSimulationConfig {
  const HeartRateSimulationConfig({this.bpm = 124, this.batteryPercent = 86});

  factory HeartRateSimulationConfig.fromRuntime(RuntimeMap value) =>
      HeartRateSimulationConfig(
        bpm: _asInt(value['bpm']) ?? 124,
        batteryPercent: _asInt(value['batteryPercent']) ?? 86,
      );

  final int bpm;
  final int batteryPercent;

  RuntimeMap toRuntime() => {'bpm': bpm, 'batteryPercent': batteryPercent};
}

final class HeartRateThresholdConfig {
  const HeartRateThresholdConfig({
    this.threshold = 150,
    this.hysteresis = 3,
    this.cooldownSeconds = 0,
  });

  factory HeartRateThresholdConfig.fromRuntime(RuntimeMap value) =>
      HeartRateThresholdConfig(
        threshold: _number(value['threshold'], fallback: 150),
        hysteresis: _number(value['hysteresis'], fallback: 3).clamp(0, 1000),
        cooldownSeconds: _number(
          value['cooldownSeconds'],
          fallback: 0,
        ).clamp(0, 86400).toInt(),
      );

  final num threshold;
  final num hysteresis;
  final int cooldownSeconds;

  RuntimeMap toRuntime() => {
    'threshold': threshold,
    'hysteresis': hysteresis,
    'cooldownSeconds': cooldownSeconds,
  };
}

final class HeartRateDeviceConnectedEvent {
  const HeartRateDeviceConnectedEvent({required this.deviceName, this.battery});

  factory HeartRateDeviceConnectedEvent.fromRuntime(RuntimeMap value) =>
      HeartRateDeviceConnectedEvent(
        deviceName: value['deviceName']?.toString() ?? '',
        battery: _asInt(value['battery']),
      );

  final String deviceName;
  final int? battery;

  RuntimeMap toRuntime() => {
    'deviceName': deviceName,
    if (battery != null) 'battery': battery,
  };
}

final class HeartRateDeviceDisconnectedEvent {
  const HeartRateDeviceDisconnectedEvent({
    required this.deviceName,
    required this.reason,
  });

  factory HeartRateDeviceDisconnectedEvent.fromRuntime(RuntimeMap value) =>
      HeartRateDeviceDisconnectedEvent(
        deviceName: value['deviceName']?.toString() ?? '',
        reason: value['reason']?.toString() ?? '',
      );

  final String deviceName;
  final String reason;

  RuntimeMap toRuntime() => {'deviceName': deviceName, 'reason': reason};
}

final class HeartRateZoneChangedEvent {
  const HeartRateZoneChangedEvent({
    required this.bpm,
    this.previousZone,
    this.zone,
    this.zoneIndex,
  });

  factory HeartRateZoneChangedEvent.fromRuntime(RuntimeMap value) =>
      HeartRateZoneChangedEvent(
        bpm: _number(value['bpm'], fallback: 0),
        previousZone: value['previousZone']?.toString(),
        zone: value['zone']?.toString(),
        zoneIndex: _asInt(value['zoneIndex']),
      );

  final num bpm;
  final String? previousZone;
  final String? zone;
  final int? zoneIndex;

  RuntimeMap toRuntime() => {
    'bpm': bpm,
    if (previousZone != null) 'previousZone': previousZone,
    if (zone != null) 'zone': zone,
    if (zoneIndex != null) 'zoneIndex': zoneIndex,
  };
}

final class HeartRateThresholdEvent {
  const HeartRateThresholdEvent({required this.bpm, required this.threshold});

  factory HeartRateThresholdEvent.fromRuntime(RuntimeMap value) =>
      HeartRateThresholdEvent(
        bpm: _number(value['bpm'], fallback: 0),
        threshold: _number(value['threshold'], fallback: 0),
      );

  final num bpm;
  final num threshold;

  RuntimeMap toRuntime() => {'bpm': bpm, 'threshold': threshold};
}

final class HeartRateEmptyConfigCodec
    implements PluginConfigCodec<HeartRateEmptyConfig> {
  const HeartRateEmptyConfigCodec();

  @override
  HeartRateEmptyConfig decode(RuntimeMap value) => const HeartRateEmptyConfig();

  @override
  RuntimeMap encode(HeartRateEmptyConfig value) => value.toRuntime();
}

final class HeartRateSimulationConfigCodec
    implements PluginConfigCodec<HeartRateSimulationConfig> {
  const HeartRateSimulationConfigCodec();

  @override
  HeartRateSimulationConfig decode(RuntimeMap value) =>
      HeartRateSimulationConfig.fromRuntime(value);

  @override
  RuntimeMap encode(HeartRateSimulationConfig value) => value.toRuntime();
}

final class HeartRateThresholdConfigCodec
    implements PluginConfigCodec<HeartRateThresholdConfig> {
  const HeartRateThresholdConfigCodec();

  @override
  HeartRateThresholdConfig decode(RuntimeMap value) =>
      HeartRateThresholdConfig.fromRuntime(value);

  @override
  RuntimeMap encode(HeartRateThresholdConfig value) => value.toRuntime();
}

const heartRateEmptyConfigCodec = HeartRateEmptyConfigCodec();
const heartRateSimulationConfigCodec = HeartRateSimulationConfigCodec();
const heartRateThresholdConfigCodec = HeartRateThresholdConfigCodec();

int? _asInt(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value');

num _number(Object? value, {required num fallback}) =>
    value is num ? value : num.tryParse('$value') ?? fallback;
