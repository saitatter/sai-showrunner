import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';
import 'package:showrunner_flutter/services/update_check_service.dart';
import 'package:showrunner_flutter/persistence/resource_repository.dart';

import '../support/showrunner_test_app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('captures the parity workspace catalog', (tester) async {
    final directory = await createShowRunnerFixtureDirectory();
    addTearDown(() => directory.delete(recursive: true));
    await _seedParityResources(directory);
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
            clock: () => DateTime(2026, 9, 23, 6, 17),
            fetcher: () async =>
                throw const HttpException('No published versions on GitHub'),
          ),
        ),
      ),
    );
    await _pumpApplication(tester);

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
    await tester.tap(find.text('Check for updates'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('No published versions on GitHub'), findsOneWidget);
    await _capture(tester, 'updater.png');

    await tester.tap(find.text('Integrations').first);
    await _pumpApplication(tester);
    expect(find.text('Integrations').last, findsOneWidget);
    await _capture(tester, 'integrations.png');

    await _scrollProjectPanelTo(tester, 'Twitch');
    await tester.tap(find.text('Twitch').last);
    await _pumpApplication(tester);
    expect(find.text('Twitch').last, findsOneWidget);
    await _capture(tester, 'twitch-workspace.png');

    await _scrollProjectPanelTo(tester, 'YouTube');
    await tester.tap(find.text('YouTube').last);
    await _pumpApplication(tester);
    expect(find.text('YouTube').last, findsOneWidget);
    await _capture(tester, 'youtube-workspace.png');

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

    await _openCatalogResource(tester, 'Profiles', 'Parity Profile');
    expect(find.text('Parity Profile'), findsAtLeastNWidgets(1));
    await _capture(tester, 'profile-editor.png');

    await _openCatalogResource(tester, 'Stream Plans', 'Parity Stream Plan');
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Segments'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
    await _capture(tester, 'stream-plan-editor.png');

    final planNameField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.controller?.text == 'Parity Stream Plan',
    );
    expect(planNameField, findsOneWidget);
    await tester.enterText(planNameField, 'Updated Parity Plan');
    await _pumpApplication(tester);
    expect(find.text('Updated Parity Plan'), findsAtLeastNWidgets(1));
    await tester.tap(
      find.ancestor(
        of: find.byTooltip('Close Updated Parity Plan tab'),
        matching: find.byType(IconButton),
      ),
    );
    await _pumpApplication(tester);
    expect(
      find.text('Save changes to Updated Parity Plan before closing?'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await _pumpApplication(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await _pumpApplication(tester);
    final savedPlan = await ResourceRepository(
      Directory('${directory.path}/stream-plans'),
      resourceType: 'StreamPlan',
    ).load('parity-plan');
    expect(savedPlan?.name, 'Updated Parity Plan');

    await _openCatalogResource(tester, 'Overlays', 'Parity Overlay');
    expect(find.text('Stream Title'), findsAtLeastNWidgets(1));
    await _capture(tester, 'overlay-editor.png');
  });
}

Future<void> _seedParityResources(Directory directory) async {
  final fixture = File('../../test/fixtures/visual-parity/resources.json');
  if (!await fixture.exists()) {
    throw StateError('Shared main/Flutter visual fixture was not found.');
  }
  final resources = jsonDecode(await fixture.readAsString()) as Map;
  for (final group in resources.entries) {
    final resourceDirectory = Directory('${directory.path}/${group.key}');
    await resourceDirectory.create(recursive: true);
    final groupResources = group.value as Map;
    for (final resource in groupResources.entries) {
      await File(
        '${resourceDirectory.path}/${resource.key}.yaml',
      ).writeAsString(jsonEncode(resource.value));
    }
  }
}

Future<void> _openCatalogResource(
  WidgetTester tester,
  String group,
  String resource,
) async {
  final panel = find.byKey(const ValueKey('showrunner-project-panel-scroll'));
  final resourceLabel = find.descendant(
    of: panel,
    matching: find.text(resource),
  );
  if (!tester.any(resourceLabel)) {
    final groupLabel = find.descendant(of: panel, matching: find.text(group));
    if (!tester.any(groupLabel)) {
      throw StateError('Project panel group "$group" was not found.');
    }
    await tester.ensureVisible(groupLabel.first);
    await tester.tap(groupLabel.first);
    await _pumpApplication(tester);
  }

  await _scrollProjectPanelTo(tester, resource);
  final target = find.descendant(of: panel, matching: find.text(resource));
  await tester.tap(target.last);
  await _pumpApplication(tester);
}

Future<void> _capture(WidgetTester tester, String fileName) async {
  if (Platform.environment['SHOWRUNNER_VISUAL_CAPTURE'] != '1') return;
  await _dismissToasts(tester);
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

Future<void> _dismissToasts(WidgetTester tester) async {
  final toast = find.byKey(const ValueKey('showrunner-toast'));
  final dismissButton = find.byKey(const ValueKey('showrunner-toast-dismiss'));
  for (var attempt = 0; attempt < 3 && tester.any(toast); attempt++) {
    final box = tester.renderObject<RenderBox>(dismissButton.last);
    await tester.tapAt(box.localToGlobal(box.size.center(Offset.zero)));
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(toast, findsNothing, reason: 'Capture must not include a toast.');
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
