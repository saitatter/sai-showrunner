import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/components/data_inputs/data_input.dart';
import 'package:showrunner_flutter/components/data_inputs/overlay_style_inputs.dart';
import 'package:showrunner_flutter/design_system/brand_icons.dart';
import 'package:showrunner_flutter/plugins/overlays/generated_widget_catalog.dart';
import 'package:showrunner_flutter/schema/identifiers.dart';

void main() {
  testWidgets('shadow picker survives repeated popup dismissal and resizing', (
    tester,
  ) async {
    final label = (await GeneratedOverlayWidgetCatalog.find(
      'overlays',
      'label',
    ))!;
    final schema = label.configSchema.fields.firstWhere(
      (field) => field.key == 'font',
    );
    dynamic value = (label.defaultConfig() as Map)['font'];
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => Align(
              alignment: Alignment.bottomRight,
              child: SizedBox(
                width: 340,
                child: OverlayStyleInput(
                  schema: schema,
                  value: value,
                  onChanged: (next) => update(() => value = next),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    for (var iteration = 0; iteration < 12; iteration++) {
      await tester.tap(find.byKey(const ValueKey('overlay-font-style-font')));
      await tester.pumpAndSettle();
      tester.view.physicalSize = iteration.isEven
          ? const Size(800, 600)
          : const Size(1000, 800);
      await tester.pumpAndSettle();
      final editor = find.byKey(const ValueKey('overlay-font-editor-font'));
      final bounds = tester.getRect(editor);
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.top, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(tester.view.physicalSize.width));
      expect(bounds.bottom, lessThanOrEqualTo(tester.view.physicalSize.height));
      if (find.text('Add Shadow').evaluate().isNotEmpty) {
        await tester.tap(find.text('Add Shadow'));
        await tester.pumpAndSettle();
      }
      final color = find.byWidgetPredicate(
        (widget) =>
            widget is InputDecorator &&
            widget.decoration.labelText == 'Shadow Color',
      );
      await tester.ensureVisible(color);
      await tester.tap(color);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('color-picker-popover')),
        findsOneWidget,
      );
      final selected = iteration.isEven ? '#ef4444' : '#ffffff';
      await tester.tap(find.byTooltip(selected));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('color-picker-popover')), findsNothing);
      expect((value as Map)['shadow']['color'], selected);
      await tester.tap(find.byKey(const ValueKey('overlay-font-editor-close')));
      await tester.pumpAndSettle();
      expect(editor, findsNothing);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('parses scalar data input values', (tester) async {
    dynamic value;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DartDataInput(
            schema: const DartDataInputSchema(
              label: 'Count',
              kind: DartDataInputKind.number,
            ),
            value: 1,
            onChanged: (next) => value = next,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '42');
    expect(value, 42);
  });

  testWidgets('renders boolean and enum controls', (tester) async {
    dynamic booleanValue;
    dynamic enumValue;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              DartDataInput(
                schema: const DartDataInputSchema(
                  label: 'Enabled',
                  kind: DartDataInputKind.boolean,
                ),
                value: false,
                onChanged: (next) => booleanValue = next,
              ),
              DartDataInput(
                schema: const DartDataInputSchema(
                  label: 'Mode',
                  kind: DartDataInputKind.enumeration,
                  options: ['one', 'two'],
                ),
                value: 'one',
                onChanged: (next) => enumValue = next,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byType(Switch));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('two').last);
    expect(booleanValue, true);
    expect(enumValue, 'two');
  });

  testWidgets('allows entering a resource ID when no catalog is available', (
    tester,
  ) async {
    dynamic value;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DartDataInput(
            schema: const DartDataInputSchema(
              label: 'Account',
              kind: DartDataInputKind.resource,
              resourceType: ResourceTypeId('BlueSkyAccount'),
            ),
            value: 'account-1',
            onChanged: (next) => value = next,
          ),
        ),
      ),
    );

    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'account-2');
    expect(value, 'account-2');
  });

  testWidgets('parses array and object input values', (tester) async {
    dynamic arrayValue;
    dynamic objectValue;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              DartDataInput(
                schema: const DartDataInputSchema(
                  label: 'Items',
                  kind: DartDataInputKind.array,
                ),
                value: const ['a'],
                onChanged: (next) => arrayValue = next,
              ),
              DartDataInput(
                schema: const DartDataInputSchema(
                  label: 'Options',
                  kind: DartDataInputKind.object,
                ),
                value: const {'enabled': true},
                onChanged: (next) => objectValue = next,
              ),
            ],
          ),
        ),
      ),
    );

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'b');
    await tester.enterText(fields.at(1), '{"enabled":false}');
    expect(arrayValue, ['b']);
    expect(objectValue, {'enabled': false});
  });

  testWidgets('parses object items inside an array input', (tester) async {
    dynamic value;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DartDataInput(
            schema: const DartDataInputSchema(
              label: 'Segments',
              kind: DartDataInputKind.array,
              itemKind: DartDataInputKind.object,
            ),
            value: const [{}],
            onChanged: (next) => value = next,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField), '{"id":"segment-1"}');
    expect(value, [
      {'id': 'segment-1'},
    ]);
  });

  testWidgets('edits typed object items inside an array input', (tester) async {
    dynamic value;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DartDataInput(
            schema: const DartDataInputSchema(
              label: 'Launchers',
              kind: DartDataInputKind.array,
              itemSchema: DartDataInputSchema(
                label: 'Launcher',
                kind: DartDataInputKind.object,
                fields: [
                  DartDataInputSchema(
                    key: 'x',
                    label: 'X',
                    kind: DartDataInputKind.number,
                  ),
                  DartDataInputSchema(
                    key: 'angle',
                    label: 'Angle',
                    kind: DartDataInputKind.number,
                  ),
                ],
              ),
            ),
            value: const [
              {'x': 0, 'angle': 20},
            ],
            onChanged: (next) => value = next,
          ),
        ),
      ),
    );

    expect(find.text('Launcher'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '42');

    expect(value, [
      {'x': 42, 'angle': 20},
    ]);
  });

  testWidgets('uses the structured overlay inspector layout', (tester) async {
    final widgets = await GeneratedOverlayWidgetCatalog.load();
    final label = widgets.firstWhere(
      (definition) => definition.key == 'overlays.label',
    );
    dynamic value;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DartDataInput(
              schema: label.configSchema,
              value: label.defaultConfig(),
              onChanged: (next) => value = next,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Font'), findsOneWidget);
    final fontControl = find.byKey(const ValueKey('overlay-font-style-font'));
    expect(fontControl, findsOneWidget);
    expect(find.text('Font Family'), findsNothing);
    await tester.tap(fontControl);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('overlay-font-family-dropdown')),
      findsOneWidget,
    );
    expect(find.text('Size'), findsOneWidget);
    expect(find.text('Font Color'), findsOneWidget);
    expect(find.text('Stroke:'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('overlay-font-editor-close')));
    await tester.pumpAndSettle();
    expect(find.text('Text Align'), findsOneWidget);
    expect(find.text('Block'), findsOneWidget);
    expect(find.text('Horizontal alignment'), findsNothing);
    expect(find.text('Margin'), findsNothing);
    expect(find.text('Padding'), findsNothing);
    expect(find.text('Vertical alignment'), findsOneWidget);

    await tester.tap(find.byIcon(mdiIcon(0xF0260)));
    expect((value as Map)['textAlign'], {'textAlign': 'center'});
  });

  testWidgets('inserts a template variable from the editor picker', (
    tester,
  ) async {
    dynamic value;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DartDataInput(
            schema: const DartDataInputSchema(
              label: 'Text',
              kind: DartDataInputKind.multilineText,
              template: true,
            ),
            value: 'Hello ',
            templateSuggestions: const ['viewerName', 'message'],
            onChanged: (next) => value = next,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Insert variable'));
    await tester.pumpAndSettle();
    expect(find.text('Insert variable'), findsOneWidget);
    await tester.tap(find.text('viewerName').last);
    await tester.pumpAndSettle();

    expect(value, 'Hello {{ viewerName }}');
  });
}
