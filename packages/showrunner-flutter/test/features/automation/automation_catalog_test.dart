import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/automation/automation_catalog_workspace.dart';
import 'package:showrunner_flutter/persistence/automation_repository.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';
import '../../support/graph_fixtures.dart';

void main() {
  testWidgets(
    'inspecting graph issues retains invalid entities for manual repair',
    (tester) async {
      final document = automationFixture(
        name: 'Stale graph',
        nodes: [actionFixture('start')],
        connections: [controlFixture('stale', 'start', 'missing')],
        entryNodeId: 'start',
      );
      final inspected = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AutomationCatalogWorkspace(
              dataService: ShowRunnerDataService(Directory.current),
              entriesLoader: () async => [
                AutomationCatalogEntry(
                  fileName: 'stale.yaml',
                  automation: document,
                ),
              ],
              onRepair: (automation, fileName) async {
                expect(automation.graph, document.graph);
                inspected.add(fileName);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Graph issues:'), findsOneWidget);
      await tester.tap(find.byTooltip('Inspect graph issues'));
      await tester.pumpAndSettle();
      expect(inspected, ['stale.yaml']);
      expect(document.graph.spaces[mainAutomationSpace]!.connections.keys, [
        'stale',
      ]);
      expect(find.byTooltip('Inspect graph issues'), findsOneWidget);
    },
  );
}
