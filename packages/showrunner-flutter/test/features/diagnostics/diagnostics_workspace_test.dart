import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/diagnostics/diagnostics_workspace.dart';
import 'package:showrunner_flutter/plugins/runtime/provider_event_workers.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/runtime/action_queue.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';
import 'package:showrunner_flutter/app/startup_health.dart';

void main() {
  testWidgets('renders provider worker state and failure details', (
    tester,
  ) async {
    final hub = DartPluginEventHub();
    final providerEvents = ProviderEventRuntime(
      dataService: ShowRunnerDataService(
        Directory('${Directory.systemTemp.path}/missing-diagnostics-data'),
      ),
      eventHub: hub,
    );
    providerEvents.youtube = YouTubeLiveChatWorker(
      liveChatId: 'chat-1',
      eventHub: hub,
      onStatusChanged: providerEvents.notifyListeners,
      request: (method, path, query, body) async {
        throw StateError('YouTube is offline');
      },
    );
    await providerEvents.youtube!.pollOnce();
    final queue = DartActionQueue();

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DiagnosticsWorkspace(
              healthFuture: Future.value(
                const StartupHealthSnapshot(state: StartupHealthState.ready),
              ),
              queue: queue,
              providerEvents: providerEvents,
              registryFuture: Future.value(DartPluginRegistry()),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('YouTube Live Chat'), findsOneWidget);
      expect(find.textContaining('Error'), findsOneWidget);
      expect(find.textContaining('attempts 1'), findsOneWidget);
      expect(find.textContaining('YouTube is offline'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await queue.dispose();
      await hub.dispose();
    }
  });
}
