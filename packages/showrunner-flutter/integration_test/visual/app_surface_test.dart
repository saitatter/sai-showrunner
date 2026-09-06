import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
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
}

Future<void> _writeOptionalCapture(WidgetTester tester) async {
  if (Platform.environment['SHOWRUNNER_VISUAL_CAPTURE'] != '1') return;
  final outputDirectory = Directory(
    Platform.environment['SHOWRUNNER_VISUAL_OUTPUT'] ??
        'test/reference/flutter',
  );
  await outputDirectory.create(recursive: true);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('showrunner-visual-surface')),
  );
  final image = await boundary.toImage(pixelRatio: 1);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('Flutter did not produce PNG bytes.');
    await File(
      '${outputDirectory.path}/app-empty.png',
    ).writeAsBytes(bytes.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}
