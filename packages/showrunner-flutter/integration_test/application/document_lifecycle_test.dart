import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:showrunner_flutter/persistence/automation_repository.dart';
import 'package:showrunner_flutter/schema/automation.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

import '../support/showrunner_test_app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('opens, closes, and reopens a persisted automation', (
    tester,
  ) async {
    final directory = await createShowRunnerFixtureDirectory();
    addTearDown(() => directory.delete(recursive: true));
    final dataService = ShowRunnerDataService(directory);
    const fileName = 'e2e-automation.yaml';
    await AutomationRepository(
      File('${directory.path}/automations/$fileName'),
    ).save(
      const AutomationData(
        extra: {'name': 'E2E Automation'},
        graph: AutomationGraph(entryNodeId: ''),
      ),
    );

    await tester.pumpWidget(buildShowRunnerTestApp(dataService: dataService));
    await _pumpApplication(tester);

    expect(
      find.bySemanticsLabel('ShowRunner desktop application'),
      findsOneWidget,
    );
    await tester.tap(find.text('Automations').first);
    await _pumpUntilVisible(tester, find.text('E2E Automation'));
    await tester.tap(find.text('E2E Automation'));
    await _pumpApplication(tester);
    expect(find.text('E2E Automation'), findsAtLeastNWidgets(1));
    expect(find.byTooltip('Close $fileName'), findsOneWidget);

    await tester.tap(find.byTooltip('Close $fileName'));
    await _pumpApplication(tester);
    expect(find.byTooltip('Close $fileName'), findsNothing);

    await _pumpUntilVisible(tester, find.text('E2E Automation'));
    await tester.tap(find.text('E2E Automation'));
    await _pumpApplication(tester);

    final automations = Directory('${directory.path}/automations');
    final files = await automations
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.yaml'))
        .toList();
    expect(files, hasLength(1));
    expect(find.byTooltip('Close ${_fileName(files.single)}'), findsOneWidget);
  });
}

String _fileName(FileSystemEntity entity) => entity.uri.pathSegments.last;

Future<void> _pumpApplication(WidgetTester tester) async {
  // Runtime workers keep timers alive, so pumpAndSettle would wait forever.
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _pumpUntilVisible(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 150));
  }
  throw TestFailure('Timed out waiting for $finder.');
}
