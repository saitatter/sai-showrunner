import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/overlays/ui/editor/overlay_editor.dart';
import 'package:showrunner_flutter/schema/resource.dart';
import 'package:showrunner_flutter/plugins/overlays/ui/editor/overlay_widget_inspector.dart';

void main() {
  void viewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  ResourceData resource(String id, {Map<String, dynamic>? preview}) =>
      ResourceData(
        id: id,
        config: {
          'name': id,
          'size': {'width': 1920, 'height': 1080},
          'widgets': [],
          'preview': ?preview,
        },
      );
  Widget app(ResourceData value, ValueChanged<ResourceData> save) =>
      MaterialApp(
        home: Scaffold(
          body: OverlayEditorPage(
            resource: value,
            onSave: (value) async => save(value),
          ),
        ),
      );
  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Preview settings'));
    await tester.pumpAndSettle();
  }

  Future<void> done(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextButton, 'Done'));
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
  }

  testWidgets('an old preview dialog cannot change another document', (
    tester,
  ) async {
    viewport(tester);
    ResourceData? saved;
    await tester.pumpWidget(
      app(
        resource(
          'old',
          preview: {'source': 'image.png', 'offsetX': 1, 'offsetY': 2},
        ),
        (value) => saved = value,
      ),
    );
    await tester.pumpAndSettle();
    await open(tester);
    await tester.pumpWidget(app(resource('new'), (value) => saved = value));
    await tester.pumpAndSettle();
    // The old dialog keeps its own fields even though its document is gone.
    await tester.enterText(find.widgetWithText(TextField, 'Offset X'), '-12.5');
    await done(tester);
    await save(tester);
    expect(saved!.id, 'new');
    expect(saved!.config.containsKey('preview'), isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('editing preview preserves unknown nested configuration', (
    tester,
  ) async {
    viewport(tester);
    ResourceData? saved;
    await tester.pumpWidget(
      app(
        resource(
          'one',
          preview: {
            'source': 'image.png',
            'offsetX': 1,
            'offsetY': 2,
            'metadata': {'label': 'keep'},
          },
        ),
        (value) => saved = value,
      ),
    );
    await tester.pumpAndSettle();
    await open(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Offset X'), '-12.5');
    await done(tester);
    await save(tester);
    expect(saved!.config['preview'], {
      'source': 'image.png',
      'offsetX': -12.5,
      'offsetY': 2,
      'metadata': {'label': 'keep'},
    });
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('disabled preview retains its form draft across reopening', (
    tester,
  ) async {
    viewport(tester);
    ResourceData? saved;
    await tester.pumpWidget(
      app(
        resource(
          'one',
          preview: {'source': 'image.png', 'offsetX': -3.25, 'offsetY': 2},
        ),
        (value) => saved = value,
      ),
    );
    await tester.pumpAndSettle();
    await open(tester);
    await tester.tap(find.widgetWithText(SwitchListTile, 'Enable preview'));
    await tester.pumpAndSettle();
    await done(tester);
    await save(tester);
    expect(saved!.config.containsKey('preview'), isFalse);
    await open(tester);
    await tester.tap(find.widgetWithText(SwitchListTile, 'Enable preview'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Offset X'))
          .controller!
          .text,
      '-3.25',
    );
    await done(tester);
    await save(tester);
    expect((saved!.config['preview'] as Map)['source'], 'image.png');
    expect((saved!.config['preview'] as Map)['offsetX'], -3.25);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'a delayed inspector edit cannot cross documents sharing a layer ID',
    (tester) async {
      viewport(tester);
      ResourceData? saved;
      ResourceData withLayer(String id) => ResourceData(
        id: id,
        config: {
          'name': id,
          'size': {'width': 1920, 'height': 1080},
          'widgets': [
            {
              'id': 'shared',
              'name': id,
              'plugin': 'overlays',
              'widget': 'label',
              'position': {'x': 0, 'y': 0},
              'size': {'width': 200, 'height': 100},
              'config': {'message': id},
            },
          ],
        },
      );
      await tester.pumpWidget(app(withLayer('old'), (value) => saved = value));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('overlay-widget-row-title-shared')),
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      final lateResult = tester
          .widget<OverlayWidgetInspector>(find.byType(OverlayWidgetInspector))
          .onChanged;
      await tester.pumpWidget(app(withLayer('new'), (value) => saved = value));
      await tester.pumpAndSettle();
      // Models a shader/configuration dialog completing after its owner changed.
      lateResult('name', 'stale result');
      await tester.pumpAndSettle();
      await save(tester);
      expect(((saved!.config['widgets'] as List).single as Map)['name'], 'new');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
