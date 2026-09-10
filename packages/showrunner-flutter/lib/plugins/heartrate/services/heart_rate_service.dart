import 'dart:async';
import 'package:flutter/foundation.dart';

import '../ble/heart_rate_parser.dart';
import '../ble/transport.dart';
import '../ble/uuids.dart';
import 'heart_rate_stats.dart';
import 'heart_rate_zones.dart';

enum HeartRateConnectionStatus {
  disabled,
  unavailable,
  idle,
  scanning,
  connecting,
  connected,
  streaming,
  reconnecting,
  error,
}

final class HeartRateService extends ChangeNotifier {
  HeartRateService({
    required this.transport,
    this.loadSettings,
    this.saveSettings,
    this.onStateChanged,
    this.staleAfter = const Duration(seconds: 3),
  });

  final BleTransport transport;
  final Future<Map<String, dynamic>> Function()? loadSettings;
  final Future<void> Function(Map<String, dynamic> settings)? saveSettings;
  final void Function(String stateId, dynamic value)? onStateChanged;
  final Duration staleAfter;

  HeartRateConnectionStatus _status = HeartRateConnectionStatus.idle;
  BleScanResult? _device;
  BleConnection? _connection;
  void Function()? _unsubscribeMeasurement;
  void Function()? _unsubscribeDisconnected;
  Timer? _staleTimer;
  Future<List<BleScanResult>>? _scanFuture;
  HeartRateStats _stats = const HeartRateStats();
  List<double> _rrIntervalsMs = const [];
  List<HeartRateZoneConfig> _zones = defaultHeartRateZones;
  int? _bpm;
  bool _stale = true;
  bool _sensorContactSupported = false;
  bool? _sensorContactDetected;
  int? _batteryPercent;
  DateTime? _lastMeasurementAt;
  String? _lastError;
  bool _started = false;
  bool _simulation = false;
  int _malformedPacketCount = 0;
  int _packetCount = 0;

  HeartRateConnectionStatus get status => _status;
  BleScanResult? get device => _device;
  HeartRateStats get stats => _stats;
  List<HeartRateZoneConfig> get zones => List.unmodifiable(_zones);
  int? get bpm => _bpm;
  bool get stale => _stale;
  bool get simulation => _simulation;
  int? get batteryPercent => _batteryPercent;
  DateTime? get lastMeasurementAt => _lastMeasurementAt;
  String? get lastError => _lastError;
  int get packetCount => _packetCount;
  int get malformedPacketCount => _malformedPacketCount;
  List<double> get rrIntervalsMs => _rrIntervalsMs;

  Future<void> initialize() async {
    final settings =
        await (loadSettings?.call() ??
            Future<Map<String, dynamic>>.value(<String, dynamic>{}));
    final rawZones = settings['zones'];
    if (rawZones is List) {
      final parsed = [
        for (final value in rawZones)
          if (value is Map) _zoneFromJson(Map<String, dynamic>.from(value)),
      ];
      if (parsed.isNotEmpty && validateHeartRateZones(parsed).isEmpty) {
        _zones = parsed;
      }
    }
    _publishAllStates();
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    final adapter = await transport.getAdapterState();
    if (adapter != BleAdapterState.poweredOn) {
      _setStatus(HeartRateConnectionStatus.unavailable);
      _lastError = 'Bluetooth adapter is not available.';
      _publishAllStates();
      return;
    }
    _startStaleTimer();
  }

  Future<List<BleScanResult>> scan({
    Duration duration = const Duration(seconds: 2),
    bool heartRateOnly = true,
  }) {
    final active = _scanFuture;
    if (active != null) return active;
    final future = _scanInternal(
      duration: duration,
      heartRateOnly: heartRateOnly,
    );
    _scanFuture = future;
    return future.whenComplete(() => _scanFuture = null);
  }

  Future<void> cancelScan() async {
    await transport.stopScan();
    if (_status == HeartRateConnectionStatus.scanning) {
      _setStatus(HeartRateConnectionStatus.idle);
    }
  }

  Future<void> connect(String deviceId, {String? deviceName}) async {
    await cancelScan();
    await _disconnectCurrent(updateStatus: false);
    _lastError = null;
    _setStatus(HeartRateConnectionStatus.connecting);
    try {
      final connection = await transport.connect(deviceId);
      final services = await connection.discoverServices();
      final heartRateService = services.where(
        (service) =>
            HeartRateUuids.normalize(service.uuid) ==
            HeartRateUuids.heartRateService,
      );
      final service = heartRateService.firstOrNull;
      if (service == null ||
          !service.characteristicUuids.any(
            (uuid) =>
                HeartRateUuids.normalize(uuid) ==
                HeartRateUuids.heartRateMeasurement,
          )) {
        await connection.disconnect();
        throw StateError('Heart Rate Service is not available on this device.');
      }
      _connection = connection;
      _device = BleScanResult(
        id: deviceId,
        name: deviceName ?? deviceId,
        serviceUuids: [HeartRateUuids.heartRateService],
      );
      _unsubscribeDisconnected = connection.onDisconnected(_onDisconnected);
      _unsubscribeMeasurement = await connection.subscribe(
        HeartRateUuids.heartRateService,
        HeartRateUuids.heartRateMeasurement,
        _onMeasurement,
      );
      _setStatus(HeartRateConnectionStatus.connected);
      await _readBattery(services);
      _publishAllStates();
    } catch (error) {
      _lastError = error.toString();
      _setStatus(HeartRateConnectionStatus.error);
      await _disconnectCurrent(updateStatus: false);
      _publishAllStates();
      rethrow;
    }
  }

  Future<void> disconnect() async {
    _simulation = false;
    await _disconnectCurrent(updateStatus: true);
  }

  Future<void> startSimulation({int bpm = 124, int batteryPercent = 86}) async {
    if (transport is! FakeBleTransportLike) {
      throw StateError(
        'The configured BLE transport does not support simulation.',
      );
    }
    final fake = transport as FakeBleTransportLike;
    fake.updateSimulation(bpm: bpm, batteryPercent: batteryPercent);
    _simulation = true;
    await connect(fake.simulatedDeviceId, deviceName: fake.simulatedDeviceName);
    _simulation = true;
    notifyListeners();
  }

  Future<void> updateSimulation({int? bpm, int? batteryPercent}) async {
    final fake = transport;
    if (fake is! FakeBleTransportLike) return;
    fake.updateSimulation(bpm: bpm, batteryPercent: batteryPercent);
    if (batteryPercent != null) {
      _batteryPercent = batteryPercent.clamp(0, 100);
      _publishState('device', deviceState);
    }
  }

  Future<void> stopSimulation() => disconnect();

  Future<void> close() async {
    _staleTimer?.cancel();
    _staleTimer = null;
    await _disconnectCurrent(updateStatus: false);
    await transport.dispose();
    _started = false;
  }

  void resetStatistics() {
    _stats = const HeartRateStats();
    _publishState('heartRate', heartRateState);
    notifyListeners();
  }

  Future<void> saveZones(List<HeartRateZoneConfig> zones) async {
    final errors = validateHeartRateZones(zones);
    if (errors.isNotEmpty) throw ArgumentError(errors.join(' '));
    _zones = List.unmodifiable(zones);
    final settings =
        await (loadSettings?.call() ??
            Future<Map<String, dynamic>>.value(<String, dynamic>{}));
    settings['zones'] = [for (final zone in _zones) zone.toJson()];
    await saveSettings?.call(settings);
    _publishState('zone', zoneState);
    notifyListeners();
  }

  Map<String, dynamic> get connectionState => {
    'status': _status.name,
    if (_lastError != null) 'message': _lastError,
    if (_device != null) 'deviceId': _device!.id,
    if (_device != null) 'deviceName': _device!.name,
    'simulated': _simulation,
  };

  Map<String, dynamic> get heartRateState => {
    if (_bpm != null) 'bpm': _bpm,
    'stale': _stale,
    ..._stats.toJson(),
    if (_lastMeasurementAt != null)
      'lastMeasurementAt': _lastMeasurementAt!.toIso8601String(),
    'rrIntervalsMs': _rrIntervalsMs,
    'contactSupported': _sensorContactSupported,
    if (_sensorContactDetected != null)
      'contactDetected': _sensorContactDetected,
  };

  Map<String, dynamic> get deviceState => {
    if (_device != null) 'id': _device!.id,
    if (_device != null) 'name': _device!.name,
    'connected': _connection != null,
    if (_device?.rssi != null) 'rssi': _device!.rssi,
    if (_batteryPercent != null) 'batteryPercent': _batteryPercent,
  };

  Map<String, dynamic> get zoneState {
    final zone = _bpm == null ? null : heartRateZoneFor(_bpm!, _zones);
    return {if (zone != null) ...zone.toJson(), if (_bpm != null) 'bpm': _bpm};
  }

  Map<String, dynamic> get diagnostics => {
    'backend': transport.runtimeType.toString(),
    'adapter': 'poweredOn',
    'status': _status.name,
    if (_device != null) 'deviceId': _device!.id,
    if (_device != null) 'deviceName': _device!.name,
    if (_lastMeasurementAt != null)
      'lastPacketAgeMs': DateTime.now()
          .difference(_lastMeasurementAt!)
          .inMilliseconds,
    if (_bpm != null) 'lastBpm': _bpm,
    if (_batteryPercent != null) 'batteryPercent': _batteryPercent,
    'packetsReceived': _packetCount,
    'malformedPackets': _malformedPacketCount,
    if (_lastError != null) 'lastError': _lastError,
  };

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }

  Future<List<BleScanResult>> _scanInternal({
    required Duration duration,
    required bool heartRateOnly,
  }) async {
    _setStatus(HeartRateConnectionStatus.scanning);
    final results = <String, BleScanResult>{};
    final subscription = transport
        .scan(heartRateOnly: heartRateOnly)
        .listen((result) => results[result.id] = result);
    try {
      await Future<void>.delayed(duration);
    } finally {
      await subscription.cancel();
      await transport.stopScan();
      if (_status == HeartRateConnectionStatus.scanning) {
        _setStatus(HeartRateConnectionStatus.idle);
      }
    }
    return results.values.toList(growable: false);
  }

  void _onMeasurement(Uint8List packet) {
    _packetCount++;
    try {
      final measurement = parseHeartRateMeasurement(packet);
      _bpm = measurement.bpm;
      _stale = false;
      _lastMeasurementAt = DateTime.now();
      _rrIntervalsMs = measurement.rrIntervalsMs;
      _sensorContactSupported = measurement.sensorContactSupported;
      _sensorContactDetected = measurement.sensorContactDetected;
      _stats = _stats.add(measurement.bpm);
      _setStatus(HeartRateConnectionStatus.streaming);
      _publishState('heartRate', heartRateState);
      _publishState('zone', zoneState);
      _publishState('connection', connectionState);
      _publishState('device', deviceState);
      notifyListeners();
    } on HeartRatePacketFormatException catch (error) {
      _malformedPacketCount++;
      _lastError = error.message;
      _publishState('connection', connectionState);
      notifyListeners();
    }
  }

  void _onDisconnected() {
    _connection = null;
    _unsubscribeMeasurement = null;
    _unsubscribeDisconnected = null;
    _stale = true;
    _setStatus(HeartRateConnectionStatus.idle);
    _publishAllStates();
    notifyListeners();
  }

  Future<void> _disconnectCurrent({required bool updateStatus}) async {
    final unsubscribeMeasurement = _unsubscribeMeasurement;
    _unsubscribeMeasurement = null;
    unsubscribeMeasurement?.call();
    _unsubscribeDisconnected?.call();
    _unsubscribeDisconnected = null;
    final connection = _connection;
    _connection = null;
    if (connection != null) await connection.disconnect();
    _stale = true;
    if (updateStatus) _setStatus(HeartRateConnectionStatus.idle);
    _publishAllStates();
    notifyListeners();
  }

  Future<void> _readBattery(List<BleServiceInfo> services) async {
    final batteryService = services
        .where(
          (service) =>
              HeartRateUuids.normalize(service.uuid) ==
              HeartRateUuids.batteryService,
        )
        .firstOrNull;
    if (batteryService == null || _connection == null) return;
    if (!batteryService.characteristicUuids.any(
      (uuid) => HeartRateUuids.normalize(uuid) == HeartRateUuids.batteryLevel,
    )) {
      return;
    }
    try {
      final value = await _connection!.readCharacteristic(
        HeartRateUuids.batteryService,
        HeartRateUuids.batteryLevel,
      );
      if (value.isNotEmpty) _batteryPercent = value.first.clamp(0, 100);
    } on Object {
      // Battery is enrichment; it must never interrupt heart-rate streaming.
    }
  }

  void _startStaleTimer() {
    _staleTimer?.cancel();
    _staleTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final last = _lastMeasurementAt;
      final next =
          last == null || DateTime.now().difference(last) >= staleAfter;
      if (next == _stale) return;
      _stale = next;
      _publishState('heartRate', heartRateState);
      notifyListeners();
    });
  }

  void _setStatus(HeartRateConnectionStatus status) {
    if (_status == status) return;
    _status = status;
    _publishState('connection', connectionState);
  }

  void _publishState(String stateId, dynamic value) => onStateChanged?.call(
    stateId,
    value is Map ? Map<String, dynamic>.from(value) : value,
  );

  void _publishAllStates() {
    _publishState('connection', connectionState);
    _publishState('heartRate', heartRateState);
    _publishState('device', deviceState);
    _publishState('zone', zoneState);
  }
}

HeartRateZoneConfig _zoneFromJson(Map<String, dynamic> value) =>
    HeartRateZoneConfig(
      id: value['id']?.toString() ?? '',
      name: value['name']?.toString() ?? '',
      minBpm: _asInt(value['minBpm']) ?? 0,
      maxBpm: _asInt(value['maxBpm']),
      color: value['color']?.toString() ?? '#9146ff',
    );

int? _asInt(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value');
