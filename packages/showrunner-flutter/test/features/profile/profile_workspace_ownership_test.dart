import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/profile/profile_workspace.dart';
import 'package:showrunner_flutter/features/profile/profile_trigger_picker.dart';
import 'package:showrunner_flutter/graph/domain/automation_document.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_bootstrap.dart';
import 'package:showrunner_flutter/plugins/runtime/provider_event_workers.dart';
import 'package:showrunner_flutter/schema/profile.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  testWidgets('trigger picker result stays with its selected profile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('profile-view-'),
    ))!;
    final data = ShowRunnerDataService(root), hub = DartPluginEventHub();
    final events = ProviderEventRuntime(dataService: data, eventHub: hub);
    final registry = createDefaultPluginRegistry();
    final controller = ProfileWorkspaceController();
    addTearDown(
      () => tester.runAsync(() async {
        await events.stop();
        events.dispose();
        await hub.dispose();
        await registry.close();
        await root.delete(recursive: true);
      }),
    );
    await tester.runAsync(() async {
      for (final name in ['first', 'second']) {
        await data.storage
            .profile('$name.yaml')
            .save(
              ShowRunnerProfile(
                name: name,
                activationMode: 'toggle',
                triggers: const [],
                activationCondition: const {},
                activationAutomation: AutomationDocument.empty(),
                deactivationAutomation: AutomationDocument.empty(),
              ),
            );
      }
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: ProfileWorkspace(
              dataService: data,
              providerEvents: events,
              registryFuture: Future.value(registry),
              controller: controller,
            ),
          ),
        ),
      );
    });
    for (var i = 0; i < 200; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('Add Trigger').evaluate().isNotEmpty) break;
    }
    expect(controller.activeProfileFile, 'first.yaml');
    for (final size in [
      const Size(1024, 640),
      const Size(1280, 720),
      const Size(1440, 900),
      const Size(1920, 1080),
    ]) {
      for (final dpr in [1.0, 1.5]) {
        tester.view.devicePixelRatio = dpr;
        tester.view.physicalSize = size * dpr;
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '$size DPR $dpr');
        expect(find.text('Save Profile').hitTestable(), findsOneWidget);
      }
    }

    await tester.ensureVisible(find.text('Add Trigger'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.text('Add Trigger')));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileTriggerPickerDialog), findsOneWidget);
    await controller.openProfile('second.yaml');
    await tester.pump();
    await tester.tap(
      find
          .descendant(
            of: find.byType(ProfileTriggerPickerDialog),
            matching: find.byType(ListTile),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(controller.activeProfileFile, 'second.yaml');
    expect(find.text('Edit Profile *'), findsNothing);
    expect(
      find.text('Triggers are how ShowRunner responds to events.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
