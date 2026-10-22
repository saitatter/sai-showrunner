import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/overlays/ui/editor/overlay_editor.dart';
import 'package:showrunner_flutter/schema/resource.dart';

const _resource = ResourceData(
  id: 'layout',
  config: {
    'name': 'Responsive overlay',
    'size': {'width': 1920, 'height': 1080},
    'widgets': [
      {
        'id': 'label',
        'name': 'Title',
        'plugin': 'overlays',
        'widget': 'label',
        'position': {'x': 20, 'y': 20},
        'size': {'width': 500, 'height': 160},
        'config': {'message': 'Initial'},
      },
    ],
  },
);

void main() {
  Widget app({Future<void> Function(ResourceData)? save}) => MaterialApp(
    home: Scaffold(
      body: Row(
        children: [
          const SizedBox(width: 300),
          Expanded(
            child: OverlayEditorPage(
              resource: _resource,
              onSave: save ?? (_) async {},
            ),
          ),
        ],
      ),
    ),
  );
  for (final size in [
    const Size(1024, 640),
    const Size(1280, 720),
    const Size(1440, 900),
    const Size(1920, 1080),
  ]) {
    for (final dpr in [1.0, 1.5]) {
      testWidgets(
        'overlay actions fit ${size.width}x${size.height} at DPR $dpr',
        (tester) async {
          tester.view.physicalSize = size * dpr;
          tester.view.devicePixelRatio = dpr;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(app());
          await tester.pumpAndSettle();
          final save = find.widgetWithText(FilledButton, 'Save');
          expect(save.hitTestable(), findsOneWidget);
          final canvas = tester.getRect(
            find.byKey(const ValueKey('overlay-canvas-region')),
          );
          expect(canvas.width, greaterThanOrEqualTo(480));
          expect(canvas.height, greaterThan(200));
          if (size.width == 1024) {
            expect(
              find.byKey(const ValueKey('overlay-widget-sidebar')),
              findsNothing,
            );
            expect(
              find.byTooltip('Inspector and layers (Ctrl+I)').hitTestable(),
              findsOneWidget,
            );
          } else {
            expect(
              find.byKey(const ValueKey('overlay-widget-sidebar')),
              findsOneWidget,
            );
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets(
    'compact inspector keyboard toggle preserves draft and mounted input across resizing',
    (tester) async {
      tester.view.physicalSize = const Size(1024, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      ResourceData? saved;
      await tester.pumpWidget(app(save: (value) async => saved = value));
      await tester.pumpAndSettle();
      Future<void> toggle() async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
      }

      await toggle();
      await tester.tap(
        find.byKey(const ValueKey('overlay-widget-row-title-label')),
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      final field = find.widgetWithText(TextField, 'Text');
      await tester.enterText(field, 'Retained compact draft');
      await tester.pumpAndSettle();
      final editable = find.descendant(
        of: field,
        matching: find.byType(EditableText),
      );
      final originalState = tester.state(editable);
      await toggle();
      expect(field, findsNothing);
      await toggle();
      expect(tester.state(editable), same(originalState));
      tester.view.physicalSize = const Size(1440, 900);
      await tester.pumpAndSettle();
      expect(tester.state(editable), same(originalState));
      expect(find.text('Retained compact draft'), findsAtLeastNWidgets(1));
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      final label = (saved!.config['widgets'] as List).single as Map;
      expect((label['config'] as Map)['message'], 'Retained compact draft');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
