import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:showrunner_flutter/app/app_foundations.dart';
import 'package:showrunner_flutter/app/startup_health.dart';
import 'package:showrunner_flutter/editor/showrunner_graph_editor.dart';
import 'package:showrunner_flutter/features/graph/graph_workspace.dart';
import 'package:showrunner_flutter/features/graph/graph_canvas_search.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Windows graph toolbar, history, find and preview workflows', (
    tester,
  ) async {
    await windowManager.ensureInitialized();
    final originalSize = await windowManager.getSize();
    final directory = await Directory.systemTemp.createTemp(
      'editor-native-qa-',
    );
    final editor = ShowRunnerGraphEditor()..loadSampleGraph();
    addTearDown(() async {
      editor.dispose();
      await directory.delete(recursive: true);
      await windowManager.setSize(originalSize);
    });
    await windowManager.setSize(const Size(1440, 900));
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('editor-qa-frame'),
        child: MaterialApp(
          theme: buildShowRunnerTheme(),
          home: Scaffold(
            body: GraphWorkspace(
              editor: editor,
              healthFuture: Future.value(
                const StartupHealthSnapshot(state: StartupHealthState.ready),
              ),
              dataService: ShowRunnerDataService(directory),
              registryFuture: Future.value(DartPluginRegistry()),
            ),
          ),
        ),
      ),
    );
    Future<void> frames() async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> click(String tooltip) async {
      final control = find.byWidgetPredicate(
        (w) => w is IconButton && w.tooltip == tooltip,
      );
      await tester.ensureVisible(control);
      await tester.tap(control);
      await frames();
      expect(tester.takeException(), isNull, reason: tooltip);
    }

    Future<void> capture(String name) async {
      final output = Platform.environment['SHOWRUNNER_EDITOR_QA_OUTPUT'];
      if (output == null) return;
      final image = await tester
          .renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('editor-qa-frame')),
          )
          .toImage();
      try {
        final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        await Directory(output).create(recursive: true);
        await File('$output/$name.png').writeAsBytes(data.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    }

    await frames();
    await click('Fit graph');
    await capture('graph-initial');
    await click('Zoom out');
    await click('Zoom in');
    await click('Reset view');
    final snap = editor.controller.config.enableSnapToGrid;
    await click(snap ? 'Disable snap to grid' : 'Enable snap to grid');
    expect(editor.controller.config.enableSnapToGrid, !snap);
    await click(snap ? 'Enable snap to grid' : 'Disable snap to grid');
    await click('Select all nodes');
    expect(editor.controller.selectedNodeIds, hasLength(3));
    await click('Fit to selection');
    await click('Align selected horizontally');
    await click('Align selected vertically');
    await click('Distribute selected evenly');
    await click('Auto-layout');
    await click('Delete selection');
    expect(editor.controller.nodes, isEmpty);
    // The dependency records node and connected-link removals separately.
    var undoSteps = 0;
    while ((editor.controller.nodes.length < 3 ||
            editor.controller.links.length < 2) &&
        undoSteps < 10) {
      await click('Undo');
      undoSteps++;
    }
    expect(editor.controller.nodes, hasLength(3));
    expect(editor.controller.links, hasLength(2));
    for (var step = 0; step < undoSteps; step++) {
      await click('Redo');
    }
    expect(editor.controller.nodes, isEmpty);
    for (var step = 0; step < undoSteps; step++) {
      await click('Undo');
    }
    await click('Fit graph');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await frames();
    final input = find.descendant(
      of: find.byType(GraphCanvasSearch),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(input).focusNode!.hasFocus, isTrue);
    await tester.enterText(input, 'Chat');
    await frames();
    expect(editor.searchResultCount(), greaterThan(0));
    await capture('graph-find');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await frames();
    await click('Play preview playhead');
    expect(editor.previewPlaying.value, isTrue);
    await click('Pause preview playhead');
    expect(editor.previewPlaying.value, isFalse);
    await click('Reset preview playhead');
    expect(editor.previewElapsed.value, Duration.zero);
    await windowManager.setSize(const Size(1000, 720));
    await frames();
    await click('Fit graph');
    await capture('graph-compact');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
