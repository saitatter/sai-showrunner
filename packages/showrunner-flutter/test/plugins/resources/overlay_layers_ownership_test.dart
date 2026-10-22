import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/resources/resource_editor_registry.dart';
import 'package:showrunner_flutter/plugins/overlays/generated_widget_catalog.dart';
import 'package:showrunner_flutter/plugins/overlays/ui/editor/overlay_layers_panel.dart';
import 'package:showrunner_flutter/schema/resource.dart';

void main() {
  testWidgets('an open layer menu follows its layer after reordering', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final definition = (await GeneratedOverlayWidgetCatalog.load()).first;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OverlayEditorPage(
            resource: ResourceData(
              id: 'layers',
              config: {
                'name': 'Layers',
                'size': {'width': 1920, 'height': 1080},
                'widgets': [
                  definition.createWidget(widgetId: 'first'),
                  definition.createWidget(widgetId: 'second'),
                ],
              },
            ),
            onSave: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final editor = tester
        .widget<OverlayLayersPanel>(find.byType(OverlayLayersPanel))
        .editor;
    await tester.tap(
      find.byKey(const ValueKey('overlay-widget-actions-first')),
    );
    await tester.pumpAndSettle();
    editor.reorder(0, 1);
    await tester.pump();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(editor.widgets.map((w) => w['id']), ['second']);
    editor.undo();
    expect(editor.widgets.map((w) => w['id']), ['second', 'first']);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
