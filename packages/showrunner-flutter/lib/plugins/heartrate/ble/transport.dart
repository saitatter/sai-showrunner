import 'dart:typed_data';

import 'uuids.dart';

enum BleAdapterState { unknown, unavailable, poweredOff, poweredOn }

final class BleScanResult {
  const BleScanResult({
    required this.id,
    required this.name,
    required this.serviceUuids,
    this.rssi,
  });

  final String id;
  final String name;
  final List<String> serviceUuids;
  final int? rssi;

  bool get hasHeartRateService => serviceUuids
      .map(HeartRateUuids.normalize)
      .contains(HeartRateUuids.heartRateService);
}

final class BleServiceInfo {
  const BleServiceInfo({
    required this.uuid,
    this.characteristicUuids = const [],
  });

  final String uuid;
  final List<String> characteristicUuids;
}

abstract interface class BleConnection {
  String get deviceId;

  Future<List<BleServiceInfo>> discoverServices();

  Future<void Function()> subscribe(
    String serviceUuid,
    String characteristicUuid,
    void Function(Uint8List data) onData,
  );

  Future<Uint8List> readCharacteristic(
    String serviceUuid,
    String characteristicUuid,
  );

  Future<void> disconnect();

  void Function() onDisconnected(void Function() callback);
}

abstract interface class BleTransport {
  Future<BleAdapterState> getAdapterState();

  Stream<BleScanResult> scan({bool heartRateOnly = true});

  Future<BleConnection> connect(String deviceId);

  Future<void> stopScan();

  Future<void> dispose();
}

/// Optional controls exposed by deterministic development transports.
abstract interface class FakeBleTransportLike implements BleTransport {
  String get simulatedDeviceId;
  String get simulatedDeviceName;

  void updateSimulation({int? bpm, int? batteryPercent});
}
