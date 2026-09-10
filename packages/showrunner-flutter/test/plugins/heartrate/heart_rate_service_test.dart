import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/heartrate/ble/fake_transport.dart';
import 'package:showrunner_flutter/plugins/heartrate/services/heart_rate_service.dart';

void main() {
  test(
    'fake scan, connect, and measurement share the service pipeline',
    () async {
      final transport = FakeBleTransport(
        emitMeasurements: false,
        measurementInterval: const Duration(hours: 1),
      );
      final states = <String, dynamic>{};
      final service = HeartRateService(
        transport: transport,
        onStateChanged: (id, value) => states[id] = value,
      );
      addTearDown(service.close);

      await service.initialize();
      await service.start();
      final devices = await service.scan(
        duration: const Duration(milliseconds: 150),
      );
      expect(devices.single.name, 'H808S (Simulated)');

      await service.connect(devices.single.id, deviceName: devices.single.name);
      transport.lastConnection!.emitHeartRate(142);

      expect(service.status, HeartRateConnectionStatus.streaming);
      expect(service.bpm, 142);
      expect(service.stats.sampleCount, 1);
      expect(service.zoneState['id'], 'zone-4');
      expect(states['heartRate']['bpm'], 142);
    },
  );

  test(
    'malformed packets update diagnostics without breaking streaming',
    () async {
      final transport = FakeBleTransport(emitMeasurements: false);
      final service = HeartRateService(transport: transport);
      addTearDown(service.close);

      await service.startSimulation();
      transport.lastConnection!.emitHeartRate(110);
      expect(service.bpm, 110);
      transport.lastConnection!.emitRaw(Uint8List.fromList([0]));
      expect(service.packetCount, 2);
      expect(service.malformedPacketCount, 1);
      expect(service.bpm, 110);
    },
  );

  test(
    'simulation can update BPM and battery without a second connection',
    () async {
      final transport = FakeBleTransport(emitMeasurements: false);
      final service = HeartRateService(transport: transport);
      addTearDown(service.close);

      await service.startSimulation(bpm: 88, batteryPercent: 51);
      await service.updateSimulation(bpm: 154, batteryPercent: 44);

      expect(service.bpm, 154);
      expect(service.batteryPercent, 44);
    },
  );
}
