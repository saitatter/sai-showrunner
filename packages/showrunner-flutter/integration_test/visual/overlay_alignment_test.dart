import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:showrunner_flutter/app/app_foundations.dart';
import 'package:showrunner_flutter/features/resources/resource_editor_registry.dart';
import 'package:showrunner_flutter/schema/resource.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Windows compact overlay keeps inspector drafts and keyboard save accessible',
    (tester) async {
      await windowManager.ensureInitialized();
      final previous = await windowManager.getSize();
      addTearDown(() => windowManager.setSize(previous));
      await windowManager.setSize(const Size(1024, 640));
      ResourceData? saved;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildShowRunnerTheme(),
          home: Scaffold(
            body: Row(
              children: [
                const SizedBox(width: 300),
                Expanded(
                  child: OverlayEditorPage(
                    resource: const ResourceData(
                      id: 'compact',
                      config: {
                        'name': 'Compact overlay',
                        'size': {'width': 1920, 'height': 1080},
                        'widgets': [
                          {
                            'id': 'title',
                            'name': 'Title',
                            'plugin': 'overlays',
                            'widget': 'label',
                            'position': {'x': 20, 'y': 20},
                            'size': {'width': 500, 'height': 160},
                            'config': {'message': 'Initial'},
                          },
                        ],
                      },
                    ),
                    onSave: (value) async => saved = value,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(FilledButton, 'Save').hitTestable(),
        findsOneWidget,
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('overlay-canvas-region')))
            .width,
        greaterThanOrEqualTo(480),
      );
      await tester.tap(find.byTooltip('Inspector and layers (Ctrl+I)'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('overlay-widget-row-title-title')),
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      final text = find.widgetWithText(TextField, 'Text');
      await tester.ensureVisible(text);
      await tester.enterText(text, 'Windows compact draft');
      await tester.pumpAndSettle();
      Future<void> shortcut(LogicalKeyboardKey key) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
      }

      await shortcut(LogicalKeyboardKey.keyI);
      expect(text, findsNothing);
      await shortcut(LogicalKeyboardKey.keyS);
      expect(
        ((saved!.config['widgets'] as List).single['config'] as Map)['message'],
        'Windows compact draft',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Windows canvas snaps movement and resize with alignment guides',
    (tester) async {
      await windowManager.ensureInitialized();
      final previous = await windowManager.getSize();
      addTearDown(() => windowManager.setSize(previous));
      await windowManager.setSize(const Size(1440, 900));
      ResourceData? latest;
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('snap-frame'),
          child: MaterialApp(
            theme: buildShowRunnerTheme(),
            home: Scaffold(
              body: OverlayEditorPage(
                resource: const ResourceData(
                  id: 'snap-proof',
                  config: {
                    'name': 'Alignment guides',
                    'size': {'width': 1920, 'height': 1080},
                    'widgets': [
                      {
                        'id': 'moving',
                        'plugin': 'overlays',
                        'widget': 'label',
                        'name': 'Moving',
                        'position': {'x': 100, 'y': 100},
                        'size': {'width': 500, 'height': 300},
                        'config': {'message': 'Moving widget'},
                        'visible': true,
                      },
                      {
                        'id': 'target',
                        'plugin': 'overlays',
                        'widget': 'label',
                        'name': 'Target',
                        'position': {'x': 700, 'y': 100},
                        'size': {'width': 200, 'height': 100},
                        'config': {'message': 'Target'},
                        'locked': true,
                        'visible': true,
                      },
                    ],
                  },
                ),
                onSave: (_) async {},
                onDocumentChanged: (resource, dirty) => latest = resource,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scale =
          tester
              .getSize(find.byKey(const ValueKey('overlay-preview-stage')))
              .width /
          1920;
      Map moving() => (latest!.config['widgets'] as List).first as Map;
      final gesture = await tester.startGesture(
        tester.getCenter(
          find.byKey(const ValueKey('overlay-canvas-widget-box-moving')),
        ),
      );
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      await gesture.moveBy(Offset(97 * scale, 0));
      await tester.pumpAndSettle();
      expect(moving()['position']['x'], 200);
      expect(
        find.byKey(const ValueKey('overlay-alignment-guides')),
        findsOneWidget,
      );
      final output = Platform.environment['SHOWRUNNER_SNAP_PROOF_OUTPUT'];
      if (output != null) {
        final image = await tester
            .renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('snap-frame')),
            )
            .toImage();
        try {
          final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
          await File(output).writeAsBytes(png.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      }
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await gesture.moveBy(Offset(scale, 0));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('overlay-alignment-guides')),
        findsNothing,
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await gesture.moveBy(Offset(scale, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      final resize = await tester.startGesture(
        tester.getCenter(
          find.byKey(const ValueKey('overlay-resize-0-bottomRight')),
        ),
      );
      await resize.moveBy(const Offset(60, 0));
      await tester.pump();
      final currentRight =
          (moving()['position']['x'] as num) +
          (moving()['size']['width'] as num);
      await resize.moveBy(Offset((797 - currentRight) * scale, 0));
      await tester.pump();
      expect(moving()['size']['width'], 600);
      expect(
        find.byKey(const ValueKey('overlay-alignment-guides')),
        findsOneWidget,
      );
      await resize.up();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('overlay-alignment-guides')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.tapAt(
        tester
                .getRect(find.byKey(const ValueKey('overlay-preview-stage')))
                .bottomRight -
            const Offset(20, 20),
      );
      await tester.pumpAndSettle();
      expect(find.text('Select a widget to edit it.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('overlay-resize-0-bottomRight')),
        findsNothing,
      );
    },
  );
}
