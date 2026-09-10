// The fake connection keeps its state private while retaining a public
// constructor for transport tests.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:typed_data';

import 'transport.dart';
import 'uuids.dart';

/// Deterministic BLE backend used by tests and the development simulation.
final class FakeBleTransport implements FakeBleTransportLike {
  FakeBleTransport({
    this.bpm = 124,
    this.batteryPercent = 86,
    this.emitMeasurements = true,
    this.measurementInterval = const Duration(seconds: 1),
  });

  static const fakeDeviceId = 'fake-h808s';

  int bpm;
  int batteryPercent;
  bool emitMeasurements;
  Duration measurementInterval;
  FakeBleConnection? lastConnection;
  bool _scanning = false;

  @override
  Future<BleAdapterState> getAdapterState() async => BleAdapterState.poweredOn;

  @override
  Stream<BleScanResult> scan({bool heartRateOnly = true}) async* {
    _scanning = true;
    final result = const BleScanResult(
      id: fakeDeviceId,
      name: 'H808S (Simulated)',
      rssi: -48,
      serviceUuids: [HeartRateUuids.heartRateService],
    );
    if (!heartRateOnly || result.hasHeartRateService) yield result;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    _scanning = false;
  }

  @override
  Future<BleConnection> connect(String deviceId) async {
    if (deviceId != fakeDeviceId) {
      throw StateError('Simulated device was not found: $deviceId');
    }
    _scanning = false;
    final connection = FakeBleConnection(
      deviceId: deviceId,
      bpm: bpm,
      batteryPercent: batteryPercent,
      emitMeasurements: emitMeasurements,
      measurementInterval: measurementInterval,
    );
    lastConnection = connection;
    return connection;
  }

  @override
  Future<void> stopScan() async {
    _scanning = false;
  }

  @override
  Future<void> dispose() async {
    await lastConnection?.disconnect();
    lastConnection = null;
    _scanning = false;
  }

  bool get isScanning => _scanning;

  @override
  String get simulatedDeviceId => fakeDeviceId;

  @override
  String get simulatedDeviceName => 'H808S (Simulated)';

  @override
  void updateSimulation({int? bpm, int? batteryPercent}) {
    if (bpm != null) this.bpm = bpm.clamp(30, 220);
    if (batteryPercent != null) {
      this.batteryPercent = batteryPercent.clamp(0, 100);
    }
    lastConnection?.updateSimulation(bpm: bpm, batteryPercent: batteryPercent);
  }

  void simulateOutOfRange() => lastConnection?.simulateOutOfRange();
}

final class FakeBleConnection implements BleConnection {
  FakeBleConnection({
    required this.deviceId,
    required int bpm,
    required int batteryPercent,
    required bool emitMeasurements,
    required Duration measurementInterval,
  }) : _bpm = bpm,
       _batteryPercent = batteryPercent,
       _emitMeasurements = emitMeasurements,
       _measurementInterval = measurementInterval;

  @override
  final String deviceId;
  int _bpm;
  int _batteryPercent;
  final bool _emitMeasurements;
  final Duration _measurementInterval;
  final _measurementListeners = <void Function(Uint8List)>{};
  final _disconnectListeners = <void Function()>{};
  Timer? _timer;
  bool _disconnected = false;

  @override
  Future<List<BleServiceInfo>> discoverServices() async => const [
    BleServiceInfo(
      uuid: HeartRateUuids.heartRateService,
      characteristicUuids: [HeartRateUuids.heartRateMeasurement],
    ),
    BleServiceInfo(
      uuid: HeartRateUuids.batteryService,
      characteristicUuids: [HeartRateUuids.batteryLevel],
    ),
  ];

  @override
  Future<void Function()> subscribe(
    String serviceUuid,
    String characteristicUuid,
    void Function(Uint8List data) onData,
  ) async {
    if (_disconnected) throw StateError('Simulated device is disconnected.');
    if (HeartRateUuids.normalize(serviceUuid) !=
            HeartRateUuids.heartRateService ||
        HeartRateUuids.normalize(characteristicUuid) !=
            HeartRateUuids.heartRateMeasurement) {
      throw StateError('Simulated characteristic is not available.');
    }
    _measurementListeners.add(onData);
    if (_emitMeasurements) _startTimer();
    return () async {
      _measurementListeners.remove(onData);
      if (_measurementListeners.isEmpty) _timer?.cancel();
    };
  }

  @override
  Future<Uint8List> readCharacteristic(
    String serviceUuid,
    String characteristicUuid,
  ) async {
    if (HeartRateUuids.normalize(serviceUuid) !=
            HeartRateUuids.batteryService ||
        HeartRateUuids.normalize(characteristicUuid) !=
            HeartRateUuids.batteryLevel) {
      throw StateError('Simulated characteristic is not available.');
    }
    return Uint8List.fromList([_batteryPercent.clamp(0, 100)]);
  }

  @override
  Future<void> disconnect() async {
    if (_disconnected) return;
    _disconnected = true;
    _timer?.cancel();
    for (final listener in List<void Function()>.from(_disconnectListeners)) {
      listener();
    }
  }

  @override
  void Function() onDisconnected(void Function() callback) {
    _disconnectListeners.add(callback);
    return () => _disconnectListeners.remove(callback);
  }

  void emitHeartRate(int nextBpm) {
    final packet = Uint8List.fromList([0, nextBpm.clamp(0, 255)]);
    emitRaw(packet);
  }

  /// Injects a notification exactly at the transport boundary.
  ///
  /// This keeps parser/error handling tests independent from the fake packet
  /// builder while preserving the same callback path used by real BLE data.
  void emitRaw(Uint8List packet) {
    if (_disconnected) return;
    for (final listener in List<void Function(Uint8List)>.from(
      _measurementListeners,
    )) {
      listener(Uint8List.fromList(packet));
    }
  }

  void updateSimulation({int? bpm, int? batteryPercent}) {
    if (bpm != null) _bpm = bpm.clamp(30, 220);
    if (batteryPercent != null) _batteryPercent = batteryPercent.clamp(0, 100);
    if (_measurementListeners.isNotEmpty) emitHeartRate(_bpm);
  }

  void simulateOutOfRange() => disconnect();

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_measurementInterval, (_) => emitHeartRate(_bpm));
  }
}
