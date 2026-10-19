import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:showrunner_flutter/plugins/heartrate/ble/fake_transport.dart';
import 'package:showrunner_flutter/plugins/heartrate/contracts.dart';
import 'package:showrunner_flutter/plugins/heartrate/manifest.dart';
import 'package:showrunner_flutter/plugins/heartrate/services/heart_rate_service.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
    'runs Heart Rate through the plugin lifecycle and trigger boundary',
    () async {
      final eventHub = DartPluginEventHub();
      final transport = FakeBleTransport(
        emitMeasurements: false,
        measurementInterval: const Duration(hours: 1),
      );
      late final DartPluginRegistry registry;
      final service = HeartRateService(
        transport: transport,
        eventHub: eventHub,
        onStateChanged: (stateId, value) =>
            registry.updateState('heartrate', stateId, value),
      );
      registry = DartPluginRegistry()
        ..registerModule(createHeartRatePluginModule(service));

      addTearDown(() async {
        await registry.close();
        await eventHub.dispose();
      });

      await registry.initialize();
      await registry.start();
      await registry.invokeAction('heartrate', 'startSimulation', {
        'bpm': 124,
        'batteryPercent': 72,
      });

      expect(service.status, HeartRateConnectionStatus.connected);
      expect(service.batteryPercent, 72);
      expect(registry.stateValues('heartrate')['device'], {
        'id': FakeBleTransport.fakeDeviceId,
        'name': 'H808S (Simulated)',
        'connected': true,
        'batteryPercent': 72,
      });

      final trigger = registry.trigger(
        const TriggerKey(
          plugin: PluginId('heartrate'),
          trigger: TriggerId('above'),
        ),
      );
      expect(trigger, isA<DartTriggerContract>());
      final events = <HeartRateThresholdEvent>[];
      final subscription = trigger!
          .listenForRuntime({
            'threshold': 150,
            'hysteresis': 3,
            'cooldownSeconds': 0,
          })!
          .listen(
            (event) => events.add(HeartRateThresholdEvent.fromRuntime(event)),
          );
      addTearDown(subscription.cancel);

      final connection = transport.lastConnection!;
      connection.emitHeartRate(149);
      connection.emitHeartRate(151);
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.single.bpm, 151);

      await registry.invokeAction('heartrate', 'disconnect', const {});
      expect(service.status, HeartRateConnectionStatus.idle);
    },
  );
}
