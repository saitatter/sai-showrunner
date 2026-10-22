import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/overlays/overlay_presence.dart';
import 'package:showrunner_flutter/plugins/overlays/ui/editor/overlay_canvas.dart';
import 'package:showrunner_flutter/plugins/overlays/ui/editor/overlay_editor.dart';
import 'package:showrunner_flutter/schema/resource.dart';

class _Reader implements OverlayPresenceReader {
  OverlayPresence presence = OverlayPresence.disconnected('presence');
  @override
  Future<OverlayPresence> getPresence(String overlayId) async => presence;
  @override
  String browserSourceUrl(String overlayId) =>
      'http://localhost:8181/overlays/$overlayId';
}

class _DelayedReader implements OverlayPresenceReader {
  final old = Completer<OverlayPresence>();
  @override
  Future<OverlayPresence> getPresence(String id) => id == 'old'
      ? old.future
      : Future.value(
          const OverlayPresence(
            overlayId: 'new',
            connected: true,
            subscribers: 3,
          ),
        );
  @override
  String browserSourceUrl(String id) => 'http://localhost:8181/overlays/$id';
}

void main() {
  testWidgets('late presence reply cannot display another resource status', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final reader = _DelayedReader();
    final future = Future<OverlayPresenceReader?>.value(reader);
    Widget app(String id) => MaterialApp(
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
          presenceReaderFuture: future,
        ),
      ),
    );
    await tester.pumpWidget(app('old'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(app('new'));
    await tester.pumpAndSettle();
    expect(find.text('Connected (3)'), findsOneWidget);
    reader.old.complete(
      const OverlayPresence(overlayId: 'old', connected: true, subscribers: 10),
    );
    await tester.pumpAndSettle();
    expect(find.text('Connected (3)'), findsOneWidget);
    expect(find.text('Connected (10)'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'presence polling updates status without rebuilding authoring canvas',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final reader = _Reader();
      var canvasBuilds = 0;
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previous?.call(element, builtOnce);
        if (element.widget is OverlayCanvas) canvasBuilds++;
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previous);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OverlayEditorPage(
              resource: const ResourceData(
                id: 'presence',
                config: {
                  'name': 'Presence',
                  'size': {'width': 1920, 'height': 1080},
                  'widgets': [],
                },
              ),
              onSave: (_) async {},
              presenceReaderFuture: Future.value(reader),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final baseline = canvasBuilds;
      reader.presence = const OverlayPresence(
        overlayId: 'presence',
        connected: true,
        subscribers: 3,
      );
      await tester.pump(const Duration(milliseconds: 2600));
      await tester.pumpAndSettle();
      expect(find.text('Connected (3)'), findsOneWidget);
      expect(
        canvasBuilds,
        baseline,
        reason: 'Presence is view status, not an authoring change.',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
