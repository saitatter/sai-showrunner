import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/automation/automation_catalog_workspace.dart';
import 'package:showrunner_flutter/persistence/automation_repository.dart';
import 'package:showrunner_flutter/runtime/automation_recovery.dart';
import 'package:showrunner_flutter/schema/automation.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  testWidgets('refreshes the catalog after repairing an automation', (
    tester,
  ) async {
    var entries = <AutomationCatalogEntry>[
      const AutomationCatalogEntry(
        fileName: 'stale.yaml',
        automation: AutomationData(
          extra: {'name': 'Stale graph'},
          graph: AutomationGraph(
            nodes: [GraphNode(id: 'start', type: 'action', x: 0, y: 0)],
            edges: [GraphEdge(id: 'stale', from: 'start', to: 'missing')],
            entryNodeId: 'start',
          ),
        ),
      ),
    ];
    final repairCalls = <String>[];
    final dataService = ShowRunnerDataService(Directory.current);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AutomationCatalogWorkspace(
            dataService: dataService,
            entriesLoader: () async => entries,
            onRepair: (automation, fileName) async {
              repairCalls.add(fileName);
              entries = [
                AutomationCatalogEntry(
                  fileName: fileName,
                  automation: repairAutomation(automation),
                ),
              ];
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text('Needs repair: Edge stale ends at missing node: missing'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Repair automation graph'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(repairCalls, ['stale.yaml']);
    expect(find.text('1 nodes, 0 links'), findsOneWidget);
    expect(find.byTooltip('Repair automation graph'), findsNothing);
    expect(find.byTooltip('Open in graph editor'), findsOneWidget);
  });
}
