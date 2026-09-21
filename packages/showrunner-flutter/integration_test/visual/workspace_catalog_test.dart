import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';
import 'package:showrunner_flutter/services/update_check_service.dart';

import '../support/showrunner_test_app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('captures the parity workspace catalog', (tester) async {
    final directory = await createShowRunnerFixtureDirectory();
    addTearDown(() => directory.delete(recursive: true));
    final view = tester.view;
    view.physicalSize = const ui.Size(1440, 900);
    view.devicePixelRatio = 1;
    addTearDown(view.reset);

    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('showrunner-visual-catalog'),
        child: buildShowRunnerTestApp(
          dataService: ShowRunnerDataService(directory),
          showGraphEditor: false,
          updateService: UpdateCheckService(
            currentVersion: '2.0.0',
            fetcher: () async =>
                throw const HttpException('No published versions on GitHub'),
          ),
        ),
      ),
    );
    await _pumpApplication(tester);

    await _capture(tester, 'app-empty.png');

    await tester.tap(find.text('File').first);
    await _pumpApplication(tester);
    await tester.tap(find.text('Settings').last);
    await _pumpApplication(tester);
    expect(find.text('Settings').last, findsOneWidget);
    await _capture(tester, 'settings.png');

    await tester.tap(find.text('Help').first);
    await _pumpApplication(tester);
    await tester.tap(find.text('Updates').last);
    await _pumpApplication(tester);
    expect(find.text('Updates').last, findsOneWidget);
    await tester.tap(find.text('Check for Updates'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('No published versions on GitHub'), findsOneWidget);
    await _capture(tester, 'updater.png');

    await tester.tap(find.text('Integrations').first);
    await _pumpApplication(tester);
    expect(find.text('Integrations').last, findsOneWidget);
    await _capture(tester, 'integrations.png');

    for (final entry in const [
      ('Queues', 'queues.png'),
      ('Variables', 'variables.png'),
      ('Viewer Variables', 'viewer-variables.png'),
    ]) {
      await tester.tap(find.text(entry.$1).first);
      await _pumpApplication(tester);
      await _capture(tester, entry.$2);
    }

    // Keep the remaining tool entries in the viewport after capturing the
    // expanded integrations state above.
    for (final category in const [
      'Streaming & Chat',
      'Production & Overlays',
      'Devices & Lights',
      'Data & Utility',
    ]) {
      await _scrollProjectPanelTo(tester, category);
      await tester.tap(find.text(category).first);
    }
    await _pumpApplication(tester);
    await _scrollProjectPanelTo(tester, 'Tools');
    await tester.tap(find.text('Tools').first);
    await _pumpApplication(tester);
    for (final entry in const [
      ('Diagnostics', 'diagnostics.png'),
      ('Logs', 'logs.png'),
      ('About', 'about.png'),
    ]) {
      await _scrollProjectPanelTo(tester, entry.$1);
      await tester.tap(find.text(entry.$1).last);
      await _pumpApplication(tester);
      await _capture(tester, entry.$2);
    }
  });
}

Future<void> _capture(WidgetTester tester, String fileName) async {
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

Future<void> _pumpApplication(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _scrollProjectPanelTo(WidgetTester tester, String label) async {
  final target = find.text(label);
  final panel = find.byKey(const ValueKey('showrunner-project-panel-scroll'));
  bool isVisible() {
    if (!tester.any(target)) return false;
    final rect = tester.getRect(target.first);
    return rect.top >= 0 && rect.bottom <= 900;
  }

  for (var attempt = 0; attempt < 8 && !isVisible(); attempt++) {
    await tester.drag(panel, const Offset(0, -500));
    await tester.pump();
  }
  if (!isVisible()) {
    throw StateError('Project panel item "$label" did not become visible.');
  }
}
