import 'dart:async';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

import 'transport.dart';
import 'uuids.dart';

/// Production BLE transport backed by the platform implementation from
/// `universal_ble`.
///
/// The Heart Rate feature only depends on [BleTransport], so the native BLE
/// package stays behind this boundary and can be replaced in tests without
/// loading a Windows device or Bluetooth adapter.
final class UniversalBleTransport implements BleTransport {
  UniversalBleTransport({UniversalBleClient? client})
    : _client = client ?? const PlatformUniversalBleClient();

  final UniversalBleClient _client;

  @override
  Future<BleAdapterState> getAdapterState() async {
    final state = await _client.getBluetoothAvailabilityState();
    return switch (state) {
      AvailabilityState.poweredOn => BleAdapterState.poweredOn,
      AvailabilityState.poweredOff => BleAdapterState.poweredOff,
      AvailabilityState.unsupported ||
      AvailabilityState.unauthorized => BleAdapterState.unavailable,
      AvailabilityState.unknown ||
      AvailabilityState.resetting => BleAdapterState.unknown,
    };
  }

  @override
  Stream<BleScanResult> scan({bool heartRateOnly = true}) {
    late final StreamController<BleScanResult> results;
    StreamSubscription<BleDevice>? subscription;
    Future<void>? startFuture;
    var disposed = false;

    Future<void> disposeNative() async {
      if (disposed) return;
      disposed = true;
      await subscription?.cancel();
      try {
        await _client.stopScan();
      } on Object {
        // Cleanup should not mask the scan error that triggered it.
      }
      if (!results.isClosed) await results.close();
    }

    Future<void> start() async {
      try {
        await _client.startScan(heartRateOnly: heartRateOnly);
      } catch (error, stackTrace) {
        if (!results.isClosed) results.addError(error, stackTrace);
        await disposeNative();
      }
    }

    results = StreamController<BleScanResult>(
      onListen: () {
        subscription = _client.scanStream.listen(
          (device) {
            final result = _toScanResult(device);
            if (!heartRateOnly || result.hasHeartRateService) {
              results.add(result);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            results.addError(error, stackTrace);
          },
        );
        startFuture = start();
      },
      onCancel: () async {
        await startFuture;
        await disposeNative();
      },
    );
    return results.stream;
  }

  @override
  Future<BleConnection> connect(String deviceId) async {
    await _client.connect(deviceId);
    return UniversalBleConnection(deviceId: deviceId, client: _client);
  }

  @override
  Future<void> stopScan() => _client.stopScan();

  @override
  Future<void> dispose() async {
    // Shutdown must remain idempotent when the app is running in a headless
    // test host or while the native plugin is already unavailable.
    try {
      await _client.stopScan();
    } on Object {
      // There is no active native resource left for the transport to release.
    }
  }

  BleScanResult _toScanResult(BleDevice device) => BleScanResult(
    id: device.deviceId,
    name: device.name?.trim().isNotEmpty == true
        ? device.name!.trim()
        : device.deviceId,
    serviceUuids: List.unmodifiable(device.services),
    rssi: device.rssi,
  );
}

/// Small adapter around the static [UniversalBle] API.
///
/// Keeping this interface separate makes scan and GATT behavior testable on
/// every CI runner, without mocking platform channels or requiring hardware.
abstract interface class UniversalBleClient {
  Stream<BleDevice> get scanStream;

  Future<AvailabilityState> getBluetoothAvailabilityState();

  Future<void> startScan({required bool heartRateOnly});

  Future<void> stopScan();

  Future<void> connect(String deviceId);

  Future<void> disconnect(String deviceId);

  Future<List<BleService>> discoverServices(String deviceId);

  Stream<bool> connectionStream(String deviceId);

  Stream<Uint8List> characteristicValueStream(
    String deviceId,
    String characteristicId,
  );

  Future<void> subscribeNotifications(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  );

  Future<void> unsubscribe(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  );

  Future<Uint8List> read(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  );
}

/// [UniversalBleClient] implementation used by the packaged Flutter app.
final class PlatformUniversalBleClient implements UniversalBleClient {
  const PlatformUniversalBleClient();

  @override
  Stream<BleDevice> get scanStream => UniversalBle.scanStream;

  @override
  Future<AvailabilityState> getBluetoothAvailabilityState() =>
      UniversalBle.getBluetoothAvailabilityState();

  @override
  Future<void> startScan({required bool heartRateOnly}) =>
      UniversalBle.startScan(
        scanFilter: heartRateOnly
            ? ScanFilter(withServices: [HeartRateUuids.heartRateService])
            : null,
      );

  @override
  Future<void> stopScan() => UniversalBle.stopScan();

  @override
  Future<void> connect(String deviceId) => UniversalBle.connect(deviceId);

  @override
  Future<void> disconnect(String deviceId) => UniversalBle.disconnect(deviceId);

  @override
  Future<List<BleService>> discoverServices(String deviceId) =>
      UniversalBle.discoverServices(deviceId);

  @override
  Stream<bool> connectionStream(String deviceId) =>
      UniversalBle.connectionStream(deviceId);

  @override
  Stream<Uint8List> characteristicValueStream(
    String deviceId,
    String characteristicId,
  ) => UniversalBle.characteristicValueStream(deviceId, characteristicId);

  @override
  Future<void> subscribeNotifications(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  ) => UniversalBle.subscribeNotifications(
    deviceId,
    serviceUuid,
    characteristicUuid,
  );

  @override
  Future<void> unsubscribe(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  ) => UniversalBle.unsubscribe(deviceId, serviceUuid, characteristicUuid);

  @override
  Future<Uint8List> read(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  ) => UniversalBle.read(deviceId, serviceUuid, characteristicUuid);
}

final class UniversalBleConnection implements BleConnection {
  UniversalBleConnection({required this.deviceId, required this.client});

  @override
  final String deviceId;

  final UniversalBleClient client;

  @override
  Future<List<BleServiceInfo>> discoverServices() async {
    final services = await client.discoverServices(deviceId);
    return [
      for (final service in services)
        BleServiceInfo(
          uuid: HeartRateUuids.normalize(service.uuid),
          characteristicUuids: List.unmodifiable(
            service.characteristics.map(
              (characteristic) => HeartRateUuids.normalize(characteristic.uuid),
            ),
          ),
        ),
    ];
  }

  @override
  Future<Future<void> Function()> subscribe(
    String serviceUuid,
    String characteristicUuid,
    void Function(Uint8List data) onData,
  ) async {
    final values = client.characteristicValueStream(
      deviceId,
      characteristicUuid,
    );
    final subscription = values.listen(onData);
    try {
      await client.subscribeNotifications(
        deviceId,
        serviceUuid,
        characteristicUuid,
      );
    } catch (_) {
      await subscription.cancel();
      rethrow;
    }

    var active = true;
    return () async {
      if (!active) return;
      active = false;
      await subscription.cancel();
      await client.unsubscribe(deviceId, serviceUuid, characteristicUuid);
    };
  }

  @override
  Future<Uint8List> readCharacteristic(
    String serviceUuid,
    String characteristicUuid,
  ) => client.read(deviceId, serviceUuid, characteristicUuid);

  @override
  Future<void> disconnect() => client.disconnect(deviceId);

  @override
  void Function() onDisconnected(void Function() callback) {
    final subscription = client.connectionStream(deviceId).listen((connected) {
      if (!connected) callback();
    });
    var active = true;
    return () {
      if (!active) return;
      active = false;
      unawaited(subscription.cancel());
    };
  }
}
