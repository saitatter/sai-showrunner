import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/resources/resource_editor_registry.dart';
import 'package:showrunner_flutter/schema/resource.dart';
import 'package:showrunner_flutter/plugins/overlays/generated_widget_catalog.dart';

void main() {
  testWidgets(
    'every catalog widget opens its inspector and preserves configuration on save',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final catalog = await GeneratedOverlayWidgetCatalog.load();
      expect(catalog.length, greaterThan(10));
      for (final definition in catalog) {
        final item = definition.createWidget(widgetId: 'catalog-item');
        ResourceData? saved;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OverlayEditorPage(
                key: ValueKey(definition.key),
                resource: ResourceData(
                  id: 'catalog',
                  config: {
                    'name': definition.name,
                    'size': {'width': 1920, 'height': 1080},
                    'widgets': [item],
                  },
                ),
                onSave: (value) async => saved = value,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('overlay-widget-row-title-catalog-item')),
        );
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: definition.key);
        final transform = find.byKey(const ValueKey('overlay-transform-x'));
        await tester.ensureVisible(transform);
        await tester.enterText(transform, '42');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        final stored = (saved!.config['widgets'] as List).single as Map;
        expect(stored['position']['x'], 42, reason: definition.key);
        expect(stored['config'], item['config'], reason: definition.key);
        expect(tester.takeException(), isNull, reason: definition.key);
      }
    },
  );
  const resource = ResourceData(
    id: 'exploratory',
    config: {
      'name': 'QA overlay',
      'size': {'width': 1920, 'height': 1080},
      'widgets': <Map<String, dynamic>>[],
    },
  );

  Finder field(String label) => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );

  Future<void> mount(
    WidgetTester tester, {
    required Future<void> Function(ResourceData) save,
    ValueChanged<bool>? dirty,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OverlayEditorPage(
            resource: resource,
            onSave: save,
            onDirtyChanged: dirty,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('zero and empty dimensions keep a usable canvas and valid save', (
    tester,
  ) async {
    ResourceData? saved;
    await mount(tester, save: (value) async => saved = value);
    await tester.enterText(field('Width'), '0');
    await tester.enterText(field('Height'), '');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const ValueKey('overlay-preview-stage'))).width,
      greaterThan(0),
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved!.config['size'], {'width': 1920, 'height': 1080});
    await tester.tap(find.text('Vertical'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved!.config['size'], {'width': 1080, 'height': 1920});
  });

  testWidgets(
    'pending save preserves newer edits and prevents duplicate saves',
    (tester) async {
      final pending = Completer<void>();
      final dirty = <bool>[];
      final saved = <ResourceData>[];
      await mount(
        tester,
        dirty: dirty.add,
        save: (value) {
          saved.add(value);
          return saved.length == 1 ? pending.future : Future.value();
        },
      );
      await tester.enterText(field('Overlay name'), 'First edit');
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Saving…'))
            .onPressed,
        isNull,
      );
      await tester.enterText(field('Overlay name'), 'Second edit');
      pending.complete();
      await tester.pumpAndSettle();
      expect(dirty, [true]);
      expect(saved.single.config['name'], 'First edit');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(dirty, [true, false]);
      expect(saved.last.config['name'], 'Second edit');
    },
  );

  testWidgets(
    'failed save reports error and allows retry without losing edits',
    (tester) async {
      var attempts = 0;
      final dirty = <bool>[];
      await mount(
        tester,
        dirty: dirty.add,
        save: (_) async {
          if (++attempts == 1) throw StateError('Disk unavailable');
        },
      );
      await tester.enterText(field('Overlay name'), 'Keep this edit');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Could not save overlay:'), findsOneWidget);
      expect(dirty, [true]);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(dirty, [true, false]);
      expect(
        tester.widget<TextField>(field('Overlay name')).controller!.text,
        'Keep this edit',
      );
    },
  );
}
