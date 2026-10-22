import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_module.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/runtime/provider_event_workers.dart';
import 'package:showrunner_flutter/plugins/twitch/ui/twitch_workspace.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  testWidgets(
    'chat messages do not rebuild Twitch controls or request health again',
    (tester) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('twitch-view-'),
      ))!;
      final data = ShowRunnerDataService(root);
      final hub = DartPluginEventHub();
      final events = ProviderEventRuntime(dataService: data, eventHub: hub);
      var healthReads = 0, builds = 0;
      final registry = DartPluginRegistry()
        ..registerModule(
          ManifestDartPluginModule(
            const DartPluginManifest(id: PluginId('twitch'), name: 'Twitch'),
            onHealthCheck: () async {
              healthReads++;
              return true;
            },
          ),
        );
      final future = Future.value(registry);
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, once) {
        previous?.call(element, once);
        if (element.widget is TwitchWorkspace) builds++;
      };
      addTearDown(() async {
        debugOnRebuildDirtyWidget = previous;
        await tester.runAsync(() async {
          await events.stop();
          events.dispose();
          await registry.close();
          await hub.dispose();
          await root.delete(recursive: true);
        });
      });
      Widget app() => MaterialApp(
        home: Scaffold(
          body: TwitchWorkspace(
            providerEvents: events,
            registryFuture: future,
            dataService: data,
          ),
        ),
      );
      await tester.pumpWidget(app());
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      final baselineBuilds = builds, baselineHealth = healthReads;
      expect(baselineHealth, greaterThan(0));
      for (var i = 0; i < 30; i++) {
        hub.emit('chat', {
          'chatter_user_name': 'Tester',
          'message': 'message $i',
        });
      }
      await tester.pump();
      await tester.pump();
      expect(builds, baselineBuilds);
      expect(healthReads, baselineHealth);
      await tester.pumpWidget(app());
      await tester.pump();
      expect(healthReads, baselineHealth);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    },
  );
}
