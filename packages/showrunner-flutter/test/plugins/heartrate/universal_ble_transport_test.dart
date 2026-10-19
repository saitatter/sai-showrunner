import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/heartrate/ble/transport.dart';
import 'package:showrunner_flutter/plugins/heartrate/ble/universal_ble_transport.dart';
import 'package:showrunner_flutter/plugins/heartrate/ble/uuids.dart';
import 'package:universal_ble/universal_ble.dart';

void main() {
  late _FakeUniversalBleClient client;
  late UniversalBleTransport transport;

  setUp(() {
    client = _FakeUniversalBleClient();
    transport = UniversalBleTransport(client: client);
  });

  tearDown(() async {
    await transport.dispose();
    await client.dispose();
  });

  test(
    'maps platform adapter availability to the transport boundary',
    () async {
      client.availability = AvailabilityState.poweredOn;
      expect(await transport.getAdapterState(), BleAdapterState.poweredOn);

      client.availability = AvailabilityState.poweredOff;
      expect(await transport.getAdapterState(), BleAdapterState.poweredOff);

      client.availability = AvailabilityState.unauthorized;
      expect(await transport.getAdapterState(), BleAdapterState.unavailable);

      client.availability = AvailabilityState.resetting;
      expect(await transport.getAdapterState(), BleAdapterState.unknown);
    },
  );

  test('filters and maps native scan results', () async {
    final found = <BleScanResult>[];
    final subscription = transport.scan().listen(found.add);
    await client.scanStarted.future;

    client.emitDevice(
      BleDevice(
        deviceId: 'hrs-1',
        name: 'COOSPO H808S',
        rssi: -51,
        services: [HeartRateUuids.heartRateService],
      ),
    );
    client.emitDevice(
      BleDevice(
        deviceId: 'other-1',
        name: 'Other sensor',
        rssi: -70,
        services: [HeartRateUuids.batteryService],
      ),
    );
    await Future<void>.delayed(Duration.zero);

    await subscription.cancel();

    expect(client.lastScanHeartRateOnly, isTrue);
    expect(found, hasLength(1));
    expect(found.single.id, 'hrs-1');
    expect(found.single.name, 'COOSPO H808S');
    expect(found.single.rssi, -51);
    expect(found.single.serviceUuids, [HeartRateUuids.heartRateService]);
    expect(client.stopScanCount, 1);
  });

  test('maps GATT discovery, notifications, reads, and disconnects', () async {
    final connection = await transport.connect('hrs-1');
    expect(client.connectedDeviceId, 'hrs-1');

    final services = await connection.discoverServices();
    expect(services, hasLength(2));
    expect(services.first.uuid, HeartRateUuids.heartRateService);
    expect(services.first.characteristicUuids, [
      HeartRateUuids.heartRateMeasurement,
    ]);

    final measurement = Completer<Uint8List>();
    final unsubscribe = await connection.subscribe(
      HeartRateUuids.heartRateService,
      HeartRateUuids.heartRateMeasurement,
      measurement.complete,
    );
    client.emitValue(Uint8List.fromList([0, 142]));
    expect(await measurement.future, [0, 142]);

    final disconnected = Completer<void>();
    final removeDisconnectListener = connection.onDisconnected(
      disconnected.complete,
    );
    client.emitConnection(false);
    await disconnected.future;

    expect(
      await connection.readCharacteristic(
        HeartRateUuids.batteryService,
        HeartRateUuids.batteryLevel,
      ),
      [86],
    );
    await unsubscribe();
    removeDisconnectListener();
    await connection.disconnect();

    expect(client.subscribed, 1);
    expect(client.unsubscribed, 1);
    expect(client.disconnectedDeviceId, 'hrs-1');
  });
}

final class _FakeUniversalBleClient implements UniversalBleClient {
  final scanController = StreamController<BleDevice>.broadcast();
  final connectionController = StreamController<bool>.broadcast();
  final valueController = StreamController<Uint8List>.broadcast();
  final scanStarted = Completer<void>();

  AvailabilityState availability = AvailabilityState.unknown;
  String? connectedDeviceId;
  String? disconnectedDeviceId;
  bool? lastScanHeartRateOnly;
  int stopScanCount = 0;
  int subscribed = 0;
  int unsubscribed = 0;

  @override
  Stream<BleDevice> get scanStream => scanController.stream;

  @override
  Future<AvailabilityState> getBluetoothAvailabilityState() async =>
      availability;

  @override
  Future<void> startScan({required bool heartRateOnly}) async {
    lastScanHeartRateOnly = heartRateOnly;
    if (!scanStarted.isCompleted) scanStarted.complete();
  }

  @override
  Future<void> stopScan() async => stopScanCount++;

  @override
  Future<void> connect(String deviceId) async => connectedDeviceId = deviceId;

  @override
  Future<void> disconnect(String deviceId) async =>
      disconnectedDeviceId = deviceId;

  @override
  Future<List<BleService>> discoverServices(String deviceId) async => [
    BleService(HeartRateUuids.heartRateService, [
      BleCharacteristic(
        HeartRateUuids.heartRateMeasurement,
        const [],
        const [],
      ),
    ]),
    BleService(HeartRateUuids.batteryService, [
      BleCharacteristic(HeartRateUuids.batteryLevel, const [], const []),
    ]),
  ];

  @override
  Stream<bool> connectionStream(String deviceId) => connectionController.stream;

  @override
  Stream<Uint8List> characteristicValueStream(
    String deviceId,
    String characteristicId,
  ) => valueController.stream;

  @override
  Future<void> subscribeNotifications(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  ) async => subscribed++;

  @override
  Future<void> unsubscribe(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  ) async => unsubscribed++;

  @override
  Future<Uint8List> read(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  ) async => Uint8List.fromList([86]);

  void emitDevice(BleDevice device) => scanController.add(device);

  void emitValue(Uint8List value) => valueController.add(value);

  void emitConnection(bool connected) => connectionController.add(connected);

  Future<void> dispose() async {
    await scanController.close();
    await connectionController.close();
    await valueController.close();
  }
}
