import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/dashboard/main_dashboard_workspace.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/runtime/provider_event_workers.dart';
import 'package:showrunner_flutter/runtime/action_queue.dart';
import 'package:showrunner_flutter/schema/queue.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  testWidgets('shows the reference landing cards and setup actions', (
    tester,
  ) async {
    final dataService = ShowRunnerDataService(Directory.systemTemp);
    final queue = DartActionQueue();
    final events = ProviderEventRuntime(
      dataService: dataService,
      eventHub: DartPluginEventHub(),
    );

    final destinations = <int>[];
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
    expect(find.text('Action queues'), findsOneWidget);
    expect(find.text('Setup OBS'), findsOneWidget);
    expect(find.text('Open Twitch settings'), findsOneWidget);

    await tester.tap(find.text('Setup OBS'));
    expect(destinations, [6]);
  });
}
