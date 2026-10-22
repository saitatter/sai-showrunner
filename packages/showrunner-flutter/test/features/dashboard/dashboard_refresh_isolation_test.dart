import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/dashboard/main_dashboard_workspace.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/runtime/provider_event_workers.dart';
import 'package:showrunner_flutter/runtime/action_queue.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  testWidgets(
    'channel refresh does not rebuild the dashboard or reload its catalog',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('dashboard-view-'),
      ))!;
      final data = ShowRunnerDataService(root), hub = DartPluginEventHub();
      final events = ProviderEventRuntime(dataService: data, eventHub: hub);
      final registry = DartPluginRegistry(), queue = DartActionQueue();
      var builds = 0, loads = 0;
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, once) {
        previous?.call(element, once);
        if (element.widget is MainDashboardWorkspace) builds++;
      };
      addTearDown(() async {
        debugOnRebuildDirtyWidget = previous;
        await tester.runAsync(() async {
          await events.stop();
          events.dispose();
          await registry.close();
          await hub.dispose();
          await queue.dispose();
          await root.delete(recursive: true);
        });
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MainDashboardWorkspace(
              dataService: data,
              actionQueue: queue,
              providerEvents: events,
              registryFuture: Future.value(registry),
              onOpenWorkspace: (_) {},
              resourcesLoader: () async {
                loads++;
                return const MainDashboardData(
                  obsConnections: [],
                  queues: [],
                  streamPlans: [],
                  twitchSettings: {
                    'accessToken': 'fixture',
                    'broadcasterId': 'test',
                  },
                );
              },
            ),
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      final baseline = builds;
      await tester.ensureVisible(find.byTooltip('Refresh Twitch channel'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Refresh Twitch channel'));
      for (var i = 0; i < 200; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        if (find
            .textContaining('Channel refresh failed:')
            .evaluate()
            .isNotEmpty) {
          break;
        }
      }
      expect(builds, baseline);
      expect(loads, 1);
      expect(find.textContaining('Channel refresh failed:'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
