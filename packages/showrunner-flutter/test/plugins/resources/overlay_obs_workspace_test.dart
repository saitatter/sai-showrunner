import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/obs/overlay_source_service.dart';
import 'package:showrunner_flutter/plugins/overlays/ui/editor/overlay_canvas.dart';
import 'package:showrunner_flutter/plugins/overlays/ui/editor/overlay_editor.dart';
import 'package:showrunner_flutter/schema/resource.dart';
import '../../support/overlay_obs_fixtures.dart';

void main() {
  void viewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget app(
    String id,
    RecordingOverlayObsActions actions, {
    List<String> suggestions = const [],
  }) => MaterialApp(
    home: Scaffold(
      body: OverlayEditorPage(
        resource: ResourceData(
          id: id,
          config: {
            'name': id,
            'size': {'width': 1920, 'height': 1080},
            'widgets': [],
          },
        ),
        onSave: (_) async {},
        obsSourceService: actions,
        templateSuggestions: suggestions,
      ),
    ),
  );

  testWidgets(
    'a create dialog opened for another document cannot write a new resource',
    (tester) async {
      viewport(tester);
      final actions = RecordingOverlayObsActions();
      actions.inspectRequest = (_) async =>
          const OverlayBrowserSourceStatus(connected: true);
      await tester.pumpWidget(app('old', actions));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('overlay-create-browser-source')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Create Browser Source'), findsOneWidget);
      await tester.pumpWidget(app('new', actions));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(actions.created, isEmpty);
      expect(find.text('new'), findsAtLeastNWidgets(1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'OBS connection status changes do not rebuild the authoring canvas',
    (tester) async {
      viewport(tester);
      final actions = RecordingOverlayObsActions();
      actions.inspectRequest = (_) async =>
          const OverlayBrowserSourceStatus(connected: false);
      var canvasBuilds = 0;
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previous?.call(element, builtOnce);
        if (element.widget is OverlayCanvas) canvasBuilds++;
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previous);
      await tester.pumpWidget(app('one', actions));
      await tester.pumpAndSettle();
      final baseline = canvasBuilds;
      actions.inspectRequest = (_) async => const OverlayBrowserSourceStatus(
        connected: true,
        sourceName: 'Ready',
        isCurrent: true,
      );
      await tester.tap(find.byKey(const ValueKey('overlay-check-obs')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('overlay-browser-source-ready')),
        findsOneWidget,
      );
      expect(canvasBuilds, baseline);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('undoing a size preset refreshes the restored OBS target', (
    tester,
  ) async {
    viewport(tester);
    final actions = RecordingOverlayObsActions();
    await tester.pumpWidget(app('one', actions));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '4K'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(actions.inspected.last.width, 3840);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(actions.inspected.last.width, 1920);
    expect(actions.inspected.last.height, 1080);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('ordinary workspace rebuilds perform no additional OBS reads', (
    tester,
  ) async {
    viewport(tester);
    final actions = RecordingOverlayObsActions();
    await tester.pumpWidget(app('one', actions));
    await tester.pumpAndSettle();
    final requests = actions.inspected.length, defaults = actions.defaultReads;
    for (var i = 0; i < 4; i++) {
      await tester.pumpWidget(app('one', actions, suggestions: ['$i']));
      await tester.pumpAndSettle();
    }
    expect(actions.inspected.length, requests);
    expect(actions.defaultReads, defaults);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
