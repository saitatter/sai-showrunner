import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/app/commands/app_command.dart';
import 'package:showrunner_flutter/app/project_panel.dart';
import 'package:showrunner_flutter/app/system_bar.dart';
import 'package:showrunner_flutter/features/settings/interface_preferences.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  testWidgets('renders the reference system bar chrome', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ShowRunnerSystemBar(commands: AppCommandRegistry(const [])),
      ),
    );

    expect(find.text('File'), findsOneWidget);
    expect(find.text('Help'), findsOneWidget);
    expect(find.byType(ShowRunnerBrandMark), findsOneWidget);
  });

  testWidgets('renders project navigation as expandable groups', (
    tester,
  ) async {
    final preferences = FlutterInterfacePreferences(
      dataService: ShowRunnerDataService(Directory.systemTemp),
    );
    addTearDown(preferences.dispose);
    var selectedIndex = -1;
    final registry = DartPluginRegistry();
    addTearDown(registry.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 300,
          child: ShowRunnerProjectPanel(
            selectedIndex: 0,
            onDestinationSelected: (index) => selectedIndex = index,
            pluginRegistryFuture: Future.value(registry),
            preferences: preferences,
            selectedPluginId: null,
            onPluginSelected: (_) {},
            onPluginToggle: (_, _) async {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('ShowRunner'), findsOneWidget);
    expect(find.text('Automations'), findsOneWidget);
    expect(find.text('Integrations'), findsOneWidget);
    expect(find.text('Tools'), findsOneWidget);

    await tester.tap(find.text('Tools'));
    await tester.pump();
    expect(find.text('Automation Editor'), findsOneWidget);

    await tester.tap(find.text('Queues'));
    expect(selectedIndex, 5);
    await tester.tap(find.byIcon(Icons.chevron_right).first);
    await tester.pumpAndSettle();
    expect(find.text('All Automations'), findsOneWidget);
  });
}
