import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:showrunner_flutter/persistence/automation_repository.dart';
import 'package:showrunner_flutter/schema/automation.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

import '../support/showrunner_test_app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders the deterministic empty application surface', (
    tester,
  ) async {
    final directory = await createShowRunnerFixtureDirectory();
    addTearDown(() => directory.delete(recursive: true));
    final view = tester.view;
    view.physicalSize = const ui.Size(1440, 900);
    view.devicePixelRatio = 1;
    addTearDown(view.reset);

    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('showrunner-visual-surface'),
        child: buildShowRunnerTestApp(
          dataService: ShowRunnerDataService(directory),
          showGraphEditor: false,
        ),
      ),
    );
    // Runtime workers keep timers alive, so pumpAndSettle would wait forever.
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      find.bySemanticsLabel('ShowRunner desktop application'),
      findsOneWidget,
    );
    expect(find.text('File'), findsOneWidget);
    expect(find.text('Help'), findsOneWidget);
    await _writeOptionalCapture(tester);
  });

  testWidgets('renders the deterministic loaded graph surface', (tester) async {
    final directory = await createShowRunnerFixtureDirectory();
    addTearDown(() => directory.delete(recursive: true));
    await AutomationRepository(
      File('${directory.path}/automations/visual-automation.yaml'),
    ).save(
      const AutomationData(
        extra: {'name': 'Visual Automation'},
        graph: AutomationGraph(
          entryNodeId: 'queue',
          nodes: [
            GraphNode(
              id: 'queue',
              type: 'action',
              x: 0,
              y: 0,
              data: {'plugin': 'ShowRunner', 'action': 'addToQueue'},
            ),
            GraphNode(
              id: 'overlay',
              type: 'action',
              x: 320,
              y: 0,
              data: {'plugin': 'overlays', 'action': 'pushChatMessage'},
            ),
            GraphNode(
              id: 'scene',
              type: 'action',
              x: 640,
              y: 0,
              data: {'plugin': 'obs', 'action': 'scene'},
            ),
          ],
          edges: [
            GraphEdge(id: 'queue-overlay', from: 'queue', to: 'overlay'),
            GraphEdge(id: 'overlay-scene', from: 'overlay', to: 'scene'),
          ],
        ),
      ),
    );
    final view = tester.view;
    view.physicalSize = const ui.Size(1440, 900);
    view.devicePixelRatio = 1;
    addTearDown(view.reset);

    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('showrunner-visual-graph'),
        child: buildShowRunnerTestApp(
          dataService: ShowRunnerDataService(directory),
          loadSampleGraph: true,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Automations').first);
    await _pumpUntilVisible(tester, find.text('Visual Automation'));
    await tester.tap(find.text('Visual Automation').first);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Graph healthy'), findsOneWidget);
    expect(find.textContaining('3 nodes'), findsOneWidget);
    expect(find.text('Add node'), findsOneWidget);
    expect(find.text('ShowRunner.addToQueue'), findsNothing);
    await _writeOptionalCapture(tester, fileName: 'app-graph.png');
  });
}

Future<void> _writeOptionalCapture(
  WidgetTester tester, {
  String fileName = 'app-empty.png',
}) async {
  if (Platform.environment['SHOWRUNNER_VISUAL_CAPTURE'] != '1') return;
  final outputDirectory = Directory(
    Platform.environment['SHOWRUNNER_VISUAL_OUTPUT'] ??
        'test/reference/flutter',
  );
  await outputDirectory.create(recursive: true);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byType(RepaintBoundary).first,
  );
  final image = await boundary.toImage(pixelRatio: 1);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('Flutter did not produce PNG bytes.');
    await File(
      '${outputDirectory.path}/$fileName',
    ).writeAsBytes(bytes.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

Future<void> _pumpUntilVisible(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 150));
  }
  throw TestFailure('Timed out waiting for $finder.');
}
