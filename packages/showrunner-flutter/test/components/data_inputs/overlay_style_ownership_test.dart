import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/components/data_inputs/overlay_style_inputs.dart';
import 'package:showrunner_flutter/schema/data_input.dart';
import 'package:showrunner_flutter/features/resources/overlay/overlay_document.dart';
import 'package:showrunner_flutter/plugins/overlays/generated_widget_catalog.dart';

void main() {
  const outline = DartDataInputSchema(
    label: 'Outline',
    kind: DartDataInputKind.object,
    editor: 'widgetOutlineStyle',
    fields: [
      DartDataInputSchema(
        label: 'Width',
        key: 'width',
        kind: DartDataInputKind.number,
      ),
    ],
  );
  test(
    'normalizing styles preserves absent, null and zero-width optional effects',
    () async {
      final label = (await GeneratedOverlayWidgetCatalog.find(
        'overlays',
        'label',
      ))!;
      for (final stroke in [
        <String, dynamic>{},
        {'stroke': null},
        {
          'stroke': {'width': 0, 'color': '#000000'},
        },
      ]) {
        final normalized = mergeOverlayWidgetDefaults(label.configSchema, {
          'font': {'fontSize': 20, ...stroke},
        });
        final font = normalized['font'] as Map;
        expect(font.containsKey('stroke'), stroke.containsKey('stroke'));
        expect(font['stroke'], stroke['stroke']);
        expect(font['fontSize'], 20);
      }
    },
  );
  testWidgets('an external style value replaces a previously edited field', (
    tester,
  ) async {
    var value = <String, dynamic>{'width': 4};
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, set) {
              update = set;
              return OverlayStyleInput(
                schema: outline,
                value: value,
                onChanged: (next) => update(
                  () => value = Map<String, dynamic>.from(next as Map),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.enterText(find.widgetWithText(TextField, 'Width'), '12.5');
    await tester.pump();
    expect(value['width'], 12.5);
    update(() => value = {'width': 4});
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '4',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'partial signed decimals survive their own model echo and retain focus',
    (tester) async {
      var value = <String, dynamic>{'width': 4};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, set) => OverlayStyleInput(
                schema: outline,
                value: value,
                onChanged: (next) =>
                    set(() => value = Map<String, dynamic>.from(next as Map)),
              ),
            ),
          ),
        ),
      );
      for (final text in ['-', '-0.', '-0.25']) {
        await tester.enterText(find.byType(TextField), text);
        await tester.pump();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          text,
        );
        expect(tester.testTextInput.isVisible, isTrue);
      }
      expect(value['width'], -0.25);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('an open font editor uses external values for its next change', (
    tester,
  ) async {
    final label = (await GeneratedOverlayWidgetCatalog.find(
      'overlays',
      'label',
    ))!;
    final schema = label.configSchema.fields.firstWhere(
      (field) => field.key == 'font',
    );
    var value = Map<String, dynamic>.from(
      (label.defaultConfig() as Map)['font'] as Map,
    );
    late StateSetter update;
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, set) {
              update = set;
              return Align(
                alignment: Alignment.bottomRight,
                child: SizedBox(
                  width: 340,
                  child: OverlayStyleInput(
                    schema: schema,
                    value: value,
                    onChanged: (next) => update(
                      () => value = Map<String, dynamic>.from(next as Map),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('overlay-font-style-font')));
    await tester.pumpAndSettle();
    update(() => value = {...value, 'fontSize': 23.5, 'metadata': 'keep'});
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Shadow'));
    await tester.pumpAndSettle();
    expect(value['fontSize'], 23.5);
    expect(value['metadata'], 'keep');
    expect(value['shadow'], isA<Map>());
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
