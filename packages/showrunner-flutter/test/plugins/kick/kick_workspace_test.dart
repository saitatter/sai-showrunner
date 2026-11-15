import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/secret_settings_store.dart';
import 'package:showrunner_flutter/plugins/kick/actions.dart';
import 'package:showrunner_flutter/features/plugins/plugin_details_view.dart';
import 'package:showrunner_flutter/plugins/kick/ui/kick_workspace.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/runtime/provider_event_workers.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  testWidgets('Kick setup keeps connection actions usable with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fixture = (await tester.runAsync(() async {
      final root = await Directory.systemTemp.createTemp('kick-workspace-');
      final data = ShowRunnerDataService(
        root,
        secretSettings: SecretSettingsStore(
          directory: Directory('${root.path}/secrets'),
          encrypt: (bytes) async => bytes,
          decrypt: (bytes) async => bytes,
        ),
      );
      final hub = DartPluginEventHub();
      final registry = DartPluginRegistry()
        ..register(
          createKickPlugin(
            KickTransport(
              (_, _, _, _) async =>
                  throw StateError('No live provider in this fixture.'),
            ),
          ),
        );
      final events = ProviderEventRuntime(dataService: data, eventHub: hub);
      return (root, data, hub, registry, events);
    }))!;
    final (root, data, hub, registry, events) = fixture;
    addTearDown(
      () => tester.runAsync(() async {
        await events.stop();
        events.dispose();
        await registry.close();
        await hub.dispose();
        await root.delete(recursive: true);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 724,
              child: KickWorkspace(
                dataService: data,
                providerEvents: events,
                registryFuture: Future.value(registry),
              ),
            ),
          ),
        ),
      ),
    );
    for (
      var attempt = 0;
      attempt < 50 && !tester.any(find.byType(PluginDetailsView));
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(find.byType(PluginDetailsView), findsOneWidget);
    expect(find.text('Connect Kick').hitTestable(), findsOneWidget);
    expect(find.text('Start listener').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Connect Kick'),
      );
      button.onPressed!();
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pump();
    expect(find.textContaining('Kick operation failed.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      await tester.runAsync(() => data.loadPluginSettings('kick')),
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
