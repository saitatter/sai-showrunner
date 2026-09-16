import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:showrunner_flutter/plugins/heartrate/ble/fake_transport.dart';
import 'package:showrunner_flutter/plugins/heartrate/contracts.dart';
import 'package:showrunner_flutter/plugins/heartrate/events.dart';
import 'package:showrunner_flutter/plugins/heartrate/manifest.dart';
import 'package:showrunner_flutter/plugins/heartrate/services/heart_rate_service.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_contract.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';

void main() {
  test(
    'uses typed action and trigger contracts at the runtime boundary',
    () async {
      final hub = DartPluginEventHub();
      final service = HeartRateService(
        transport: FakeBleTransport(),
        eventHub: hub,
      );
      addTearDown(() async {
        await service.close();
        await hub.dispose();
      });
      final manifest = createHeartRatePlugin(service);
      final action = manifest.actions.firstWhere(
        (candidate) => candidate.actionId.value == 'startSimulation',
      );
      final config = action.decodeConfig({'bpm': '145', 'batteryPercent': 52});
      expect(config, isA<HeartRateSimulationConfig>());
      final simulation = config as HeartRateSimulationConfig;
      expect(simulation.bpm, 145);
      expect(simulation.batteryPercent, 52);

      final trigger = manifest.triggers.firstWhere(
        (candidate) => candidate.triggerId.value == 'above',
      );
      final threshold = trigger.decodeConfig({'threshold': 160});
      expect(threshold, isA<HeartRateThresholdConfig>());
      final typedThreshold = threshold as HeartRateThresholdConfig;
      expect(typedThreshold.threshold, 160);
    },
  );

  test('registers semantic heart-rate triggers and lifecycle actions', () {
    final service = HeartRateService(transport: FakeBleTransport());
    addTearDown(service.close);

    final manifest = createHeartRatePlugin(service);

    expect(
      manifest.actions.map((action) => action.actionId.value),
      containsAll(<String>[
        'connectPreferredDevice',
        'disconnect',
        'resetStatistics',
      ]),
    );
    expect(
      manifest.triggers,
      isEmpty,
      reason: 'triggers require the application event hub',
    );
  });

  test(
    'publishes connection and zone events through the shared event hub',
    () async {
      final hub = DartPluginEventHub();
      final transport = FakeBleTransport(emitMeasurements: false);
      final service = HeartRateService(transport: transport, eventHub: hub);
      addTearDown(() async {
        await service.close();
        await hub.dispose();
      });

      final connected = hub.stream(HeartRateEventIds.deviceConnected).first;
      await service.startSimulation(bpm: 99);
      expect((await connected)['deviceName'], 'H808S (Simulated)');

      final zoneChanged = hub.stream(HeartRateEventIds.zoneChanged).first;
      transport.lastConnection!.emitHeartRate(124);
      expect((await zoneChanged)['zone'], 'Zone 3');

      final disconnected = hub
          .stream(HeartRateEventIds.deviceDisconnected)
          .first;
      await service.disconnect();
      expect((await disconnected)['reason'], 'manual');
    },
  );

  test(
    'above trigger uses crossing, hysteresis, and cooldown semantics',
    () async {
      final hub = DartPluginEventHub();
      final transport = FakeBleTransport(emitMeasurements: false);
      final service = HeartRateService(transport: transport, eventHub: hub);
      StreamSubscription<dynamic>? subscription;
      try {
        await service.startSimulation();

        final trigger =
            createHeartRatePlugin(service).triggers.firstWhere(
                  (candidate) => candidate.triggerId.value == 'above',
                )
                as TriggerSpec<
                  HeartRateThresholdConfig,
                  HeartRateThresholdEvent
                >;
        final events = <HeartRateThresholdEvent>[];
        final config = trigger.decodeConfig({
          'threshold': 150,
          'hysteresis': 3,
          'cooldownSeconds': 0,
        });
        subscription = trigger.listenForConfig!.call(config).listen(events.add);
        await Future<void>.delayed(Duration.zero);

        final connection = transport.lastConnection!;
        connection.emitHeartRate(149);
        connection.emitHeartRate(151);
        connection.emitHeartRate(152);
        connection.emitHeartRate(146);
        connection.emitHeartRate(151);
        await Future<void>.delayed(Duration.zero);

        expect(events.map((event) => event.bpm), [151, 151]);
      } finally {
        await subscription?.cancel();
        await service.close();
        await hub.dispose();
      }
    },
  );
}
