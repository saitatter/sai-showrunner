import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:showrunner_flutter/app/app_foundations.dart';
import 'package:showrunner_flutter/features/resources/resource_editor_registry.dart';
import 'package:showrunner_flutter/schema/resource.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'nested shadow picker keeps the Windows frame intact after resizing',
    (tester) async {
      await windowManager.ensureInitialized();
      final originalSize = await windowManager.getSize();
      addTearDown(() => windowManager.setSize(originalSize));
      await tester.pumpWidget(
        MaterialApp(theme: buildShowRunnerTheme(), home: const Scaffold()),
      );
      final definition = createDefaultResourceEditorRegistry().find('Overlay')!;
      final editor = definition.builder(
        tester.element(find.byType(Scaffold)),
        const ResourceData(
          id: 'popup-rendering',
          config: {
            'name': 'Popup rendering',
            'size': {'width': 1920, 'height': 1080},
            'widgets': [
              {
                'id': 'title',
                'plugin': 'overlays',
                'widget': 'label',
                'name': 'Stream Title',
                'position': {'x': 120, 'y': 100},
                'size': {'width': 700, 'height': 160},
                'config': {
                  'message': 'LIVE - Starting soon',
                  'font': {
                    'fontFamily': 'Impact',
                    'fontSize': 65,
                    'fontColor': '#FFFFFF',
                    'stroke': {'width': 4, 'color': '#000000'},
                    'shadow': {
                      'blur': 4,
                      'color': '#FFFFFF',
                      'offsetX': 0,
                      'offsetY': 0,
                    },
                  },
                },
                'visible': true,
                'locked': false,
              },
            ],
          },
        ),
        (_) async {},
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('popup-render-frame'),
          child: MaterialApp(
            theme: buildShowRunnerTheme(),
            home: Scaffold(body: editor),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stream Title').last);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      final x = find.byKey(const ValueKey('overlay-transform-x'));
      await tester.ensureVisible(x);
      await tester.enterText(x, 'letters');
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(x).controller!.text, '120');
      for (var iteration = 0; iteration < 12; iteration++) {
        final font = find.byKey(const ValueKey('overlay-font-style-font'));
        await tester.ensureVisible(font);
        await tester.tap(font);
        await tester.pumpAndSettle();
        await windowManager.setSize(
          iteration.isEven ? const Size(1000, 720) : const Size(1440, 900),
        );
        await tester.pumpAndSettle();
        final familyInput = find.byKey(
          const ValueKey('overlay-font-family-dropdown'),
        );
        expect(
          find.descendant(of: familyInput, matching: find.byType(TextField)),
          findsNothing,
        );
        await tester.tap(familyInput);
        await tester.pumpAndSettle();
        final family = iteration.isEven ? 'Arial' : 'Impact';
        await tester.ensureVisible(
          find.widgetWithText(MenuItemButton, family).last,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(MenuItemButton, family).last);
        await tester.pumpAndSettle();
        final color = find.byWidgetPredicate(
          (widget) =>
              widget is InputDecorator &&
              widget.decoration.labelText == 'Shadow Color',
        );
        await tester.ensureVisible(color);
        await tester.tap(color);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('color-channel-R')),
          '128',
        );
        await tester.pumpAndSettle();
        if (iteration == 0) {
          final red = find.byKey(const ValueKey('color-channel-R'));
          await tester.enterText(red, '128abc');
          await tester.pumpAndSettle();
          expect(tester.widget<TextField>(red).controller!.text, '128');
        }
        await tester.enterText(
          find.byKey(const ValueKey('color-channel-A')),
          '128',
        );
        await tester.pumpAndSettle();
        await _checkFrame(tester, 'picker-$iteration');
        await tester.tap(
          find.byTooltip(iteration.isEven ? '#ef4444' : '#ffffff'),
        );
        await tester.pumpAndSettle();
        await _checkFrame(tester, 'open-$iteration');
        await tester.tap(
          find.byKey(const ValueKey('overlay-font-editor-close')),
        );
        await tester.pumpAndSettle();
        await _checkFrame(tester, 'closed-$iteration');
        expect(tester.takeException(), isNull);
      }
    },
  );
}

Future<void> _checkFrame(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('popup-render-frame')),
  );
  final image = await boundary.toImage(pixelRatio: 1);
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    var black = 0;
    final bytes = data.buffer.asUint8List();
    for (var index = 0; index < bytes.length; index += 4) {
      if (bytes[index] <= 1 &&
          bytes[index + 1] <= 1 &&
          bytes[index + 2] <= 1 &&
          bytes[index + 3] == 255) {
        black++;
      }
    }
    final fraction = black / (image.width * image.height);
    final output = Platform.environment['SHOWRUNNER_POPUP_PROOF_OUTPUT'];
    if (output != null) {
      await Directory(output).create(recursive: true);
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await File('$output/$name.png').writeAsBytes(png.buffer.asUint8List());
    }
    expect(
      fraction,
      lessThan(.015),
      reason: '$name: unexpected opaque black region in the frame',
    );
  } finally {
    image.dispose();
  }
}
