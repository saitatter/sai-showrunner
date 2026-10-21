import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/overlays/ui/editor/overlay_editor.dart';
import 'package:showrunner_flutter/schema/resource.dart';

void main() {
  testWidgets(
    'overlay keyboard history restores inputs and saves the current generation',
    (tester) async {
      ResourceData? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OverlayEditorPage(
              resource: const ResourceData(
                id: 'keys',
                config: {
                  'name': 'Keyboard',
                  'size': {'width': 1920, 'height': 1080},
                  'widgets': [],
                },
              ),
              onSave: (value) async => saved = value,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '4K'));
      await tester.pumpAndSettle();
      Future<void> shortcut(LogicalKeyboardKey key) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
      }

      String width() => tester
          .widget<TextField>(find.widgetWithText(TextField, 'Width'))
          .controller!
          .text;
      expect(width(), '3840');
      await shortcut(LogicalKeyboardKey.keyZ);
      expect(width(), '1920');
      await shortcut(LogicalKeyboardKey.keyY);
      expect(width(), '3840');
      await shortcut(LogicalKeyboardKey.keyS);
      expect((saved!.config['size'] as Map)['width'], 3840);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  ResourceData resource(String id) => ResourceData(
    id: id,
    config: {
      'name': id,
      'size': {'width': 1920, 'height': 1080},
      'widgets': [],
    },
  );
  Widget app(
    ResourceData value,
    Future<void> Function(ResourceData) save, {
    void Function(ResourceData, bool)? changed,
  }) => MaterialApp(
    home: Scaffold(
      body: OverlayEditorPage(
        resource: value,
        onSave: save,
        onDocumentChanged: changed,
      ),
    ),
  );

  testWidgets(
    'switching resource identity resets input and saves the new document',
    (tester) async {
      ResourceData? saved;
      await tester.pumpWidget(
        app(resource('first'), (value) async => saved = value),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        app(resource('second'), (value) async => saved = value),
      );
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Overlay name'),
      );
      expect(field.controller!.text, 'second');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(saved!.id, 'second');
      expect(saved!.name, 'second');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'late save cannot publish another resource draft or clear its dirty state',
    (tester) async {
      final release = Completer<void>();
      final changes = <(String, bool)>[];
      await tester.pumpWidget(
        app(
          resource('first'),
          (_) => release.future,
          changed: (value, dirty) => changes.add((value.id, dirty)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump();
      await tester.pumpWidget(
        app(
          resource('second'),
          (_) async {},
          changed: (value, dirty) => changes.add((value.id, dirty)),
        ),
      );
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'Overlay name'),
        'New draft',
      );
      await tester.pump();
      changes.clear();
      release.complete();
      await tester.pumpAndSettle();
      expect(changes, isEmpty);
      expect(find.text('New draft'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'save failure keeps the draft without echoing exception payloads',
    (tester) async {
      await tester.pumpWidget(
        app(resource('first'), (_) async => throw StateError('private-marker')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Overlay name'),
        'Retained draft',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('private-marker'), findsNothing);
      expect(find.text('Retained draft'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
