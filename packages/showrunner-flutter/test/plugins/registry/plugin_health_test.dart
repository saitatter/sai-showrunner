import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/elgato/bootstrap.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_bootstrap.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  testWidgets(
    'health probes have a bounded deadline and ignore eventual completion',
    (tester) async {
      final pending = Completer<bool>();
      final registry = DartPluginRegistry()
        ..register(
          const DartPluginManifest(id: PluginId('slow'), name: 'Slow'),
          onHealthCheck: () => pending.future,
        );
      final checking = registry.checkHealthDetailsId(const PluginId('slow'));
      await tester.pump(const Duration(seconds: 11));
      final health = await checking;
      expect(health.isHealthy, isFalse);
      expect(health.error, isA<TimeoutException>());
      pending.complete(true);
      await tester.pump();
      await registry.close();
    },
  );

  test('unconfigured providers never report a healthy connection', () async {
    final registry = createDefaultPluginRegistry();
    addTearDown(registry.close);
    for (final id in [
      'obs',
      'aitum',
      'advss',
      'twitch',
      'youtube',
      'govee',
      'philips-hue',
      'elgato',
      'tplink-kasa',
      'lifx',
      'wyze',
      'donordrive',
      'remote',
      'bluesky',
      'twinkly',
      'voicemod',
      'discord',
      'minecraft',
      'iot',
    ]) {
      final health = await registry.checkHealthDetailsId(PluginId(id));
      expect(health.status, DartPluginHealthStatus.notConfigured, reason: id);
      expect(health.isHealthy, isFalse, reason: id);
    }
    expect(
      (await registry.checkHealthDetailsId(const PluginId('random'))).isHealthy,
      isTrue,
    );
  });

  test('configuration alone is not proof of a connected device', () async {
    final directory = await Directory.systemTemp.createTemp('provider-health-');
    addTearDown(() => directory.delete(recursive: true));
    final data = ShowRunnerDataService(directory);
    await data.savePluginSettings('elgato', {'host': '127.0.0.1', 'port': 1});
    final registry = DartPluginRegistry();
    addTearDown(registry.close);
    await registerConfiguredElgato(registry, dataService: data);
    final health = await registry.checkHealthDetailsId(
      const PluginId('elgato'),
    );
    expect(health.status, DartPluginHealthStatus.disconnected);
    expect(health.isHealthy, isFalse);
    expect(health.message, contains('not been verified'));
    // This reads availability metadata; it must never contact the configured port.
  });

  test(
    'disabled health skips the provider probe while retaining its contribution',
    () async {
      var probes = 0;
      final registry = DartPluginRegistry()
        ..register(
          const DartPluginManifest(id: PluginId('sample'), name: 'Sample'),
          onHealthCheck: () async {
            probes++;
            return true;
          },
        );
      registry.setPluginEnabled('sample', false);
      final health = await registry.checkHealthDetailsId(
        const PluginId('sample'),
      );
      expect(health.status, DartPluginHealthStatus.disabled);
      expect(probes, 0);
      expect(registry.findPlugin('sample'), isNotNull);
      await registry.close();
    },
  );
}
