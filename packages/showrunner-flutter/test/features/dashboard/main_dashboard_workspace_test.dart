import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/app/workspace_registry.dart';
import 'package:showrunner_flutter/features/dashboard/main_dashboard_workspace.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/runtime/provider_event_workers.dart';
import 'package:showrunner_flutter/runtime/action_queue.dart';
import 'package:showrunner_flutter/schema/queue.dart';
import 'package:showrunner_flutter/schema/resource.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  testWidgets(
    'invalid stream plans stay visible as errors without breaking the dashboard',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final dataService = ShowRunnerDataService(Directory.systemTemp);
      final hub = DartPluginEventHub();
      final events = ProviderEventRuntime(
        dataService: dataService,
        eventHub: hub,
      );
      final registry = DartPluginRegistry();
      addTearDown(() async {
        await events.stop();
        events.dispose();
        await registry.close();
        await hub.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: MainDashboardWorkspace(
            dataService: dataService,
            actionQueue: DartActionQueue(),
            providerEvents: events,
            registryFuture: Future.value(registry),
            onOpenWorkspace: (_) {},
            resourcesLoader: () async => const MainDashboardData(
              obsConnections: [],
              queues: [],
              twitchSettings: {},
              streamPlans: [
                ResourceData(
                  id: 'invalid',
                  config: {
                    'name': 'Invalid plan',
                    'activationAutomation': {'schemaVersion': 99},
                    'segments': [],
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('Invalid stream plan:'), findsOneWidget);
      expect(find.text('Stream Plan'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('shows the reference landing cards and setup actions', (
    tester,
  ) async {
    final dataService = ShowRunnerDataService(Directory.systemTemp);
    final queue = DartActionQueue();
    final events = ProviderEventRuntime(
      dataService: dataService,
      eventHub: DartPluginEventHub(),
    );

    final destinations = <WorkspaceId>[];
    await tester.pumpWidget(
      MaterialApp(
        home: MainDashboardWorkspace(
          dataService: dataService,
          actionQueue: queue,
          providerEvents: events,
          registryFuture: Future.value(DartPluginRegistry()),
          onOpenWorkspace: destinations.add,
          resourcesLoader: () async => const MainDashboardData(
            obsConnections: [],
            queues: <({String fileName, QueueConfig? config, Object? error})>[],
            streamPlans: [],
            twitchSettings: {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('OBS'), findsOneWidget);
    expect(find.text('Twitch'), findsOneWidget);
    expect(find.text('Stream Plan'), findsOneWidget);
    expect(find.text('Action queues'), findsNothing);
    expect(find.text('Setup OBS'), findsOneWidget);
    expect(find.text('Sign into Channel'), findsOneWidget);
    expect(find.text('Sign into Bot'), findsOneWidget);
    expect(find.text('Add Tag'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);

    await tester.tap(find.text('Setup OBS'));
    expect(destinations, [WorkspaceIds.resources]);
  });
}
