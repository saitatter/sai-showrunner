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
      initialValues: {'hideNativeIntegrationShortcuts': false},
    );
    addTearDown(preferences.dispose);
    var selectedIndex = -1;
    String? selectedResourceType;
    final registry = DartPluginRegistry();
    for (final plugin in const [
      ('obs', 'OBS'),
      ('twitch', 'Twitch'),
      ('youtube', 'YouTube'),
      ('moderation', 'Moderation'),
    ]) {
      registry.register(DartPluginManifest(id: plugin.$1, name: plugin.$2));
    }
    addTearDown(registry.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 300,
          height: 1200,
          child: ShowRunnerProjectPanel(
            selectedIndex: 0,
            onDestinationSelected: (index) => selectedIndex = index,
            pluginRegistryFuture: Future.value(registry),
            preferences: preferences,
            selectedPluginId: null,
            onPluginSelected: (_) {},
            onPluginToggle: (_, _) async {},
            onResourceSelected: (resourceType) {
              selectedResourceType = resourceType;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ShowRunner'), findsOneWidget);
    expect(find.text('Automations'), findsOneWidget);
    expect(find.text('Integrations'), findsOneWidget);
    expect(find.text('Stream Plans'), findsOneWidget);
    expect(find.text('Media'), findsOneWidget);
    expect(find.text('Viewer Variables'), findsOneWidget);
    expect(find.text('OBS'), findsNWidgets(2));
    expect(find.text('Connections'), findsOneWidget);
    expect(find.text('Twitch'), findsNWidgets(2));
    expect(find.text('YouTube'), findsNWidgets(2));
    expect(find.text('Moderation'), findsNWidgets(2));
    expect(find.text('Account Login'), findsOneWidget);
    expect(find.text('Channel Point Rewards'), findsOneWidget);
    expect(find.text('Viewer Groups'), findsOneWidget);
    expect(find.text('Live Integration'), findsOneWidget);
    expect(find.text('Moderation Docker'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Connections'));
    await tester.tap(find.text('Connections'));
    expect(selectedResourceType, 'OBSConnection');

    await tester.drag(find.byType(ListView), const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(find.text('Overlays'), findsOneWidget);

    await tester.ensureVisible(find.text('Tools'));
    await tester.tap(find.text('Tools'));
    await tester.pump();
    expect(find.text('Automation Editor'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, 1000));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Queues'));
    await tester.tap(find.text('Queues'));
    expect(selectedIndex, 5);
    await tester.tap(find.byIcon(Icons.chevron_right).first);
    await tester.pumpAndSettle();
    expect(find.text('All Automations'), findsNothing);
  });
}
