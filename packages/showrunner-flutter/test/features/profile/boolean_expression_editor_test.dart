import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/profile/boolean_expression_editor.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/schema/automation.dart';

void main() {
  testWidgets('builds nested groups and value conditions visually', (
    tester,
  ) async {
    var condition = createAlwaysOnCondition();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: SizedBox(
                width: 900,
                child: BooleanExpressionEditor(
                  value: condition,
                  onChanged: (next) => setState(() => condition = next),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('No Conditions (Always On)'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Group').first);
    await tester.pumpAndSettle();
    expect(condition['operands'], hasLength(1));
    expect(find.text('No Conditions (Always On)'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Value').first);
    await tester.pumpAndSettle();
    expect(condition['operands'], hasLength(2));
    expect((condition['operands'] as List).last['type'], 'value');
    expect(find.text('Compare'), findsOneWidget);
    expect(find.text('State'), findsAtLeastNWidgets(2));
    expect(find.text('Activation condition (JSON)'), findsNothing);
  });

  test('normalizes supported root expressions without losing meaning', () {
    expect(normalizeActivationCondition({'type': 'literal', 'value': true}), {
      'type': 'group',
      'operator': 'and',
      'operands': <JsonMap>[],
    });

    final falseCondition = normalizeActivationCondition({
      'type': 'literal',
      'value': false,
    });
    expect(falseCondition['type'], 'group');
    final falseLeaf = (falseCondition['operands'] as List).single;
    expect(falseLeaf['type'], 'value');
    expect(falseLeaf['lhs']['value'], isFalse);
    expect(falseLeaf['rhs']['value'], isTrue);

    final group = <String, dynamic>{
      'type': 'group',
      'operator': 'or',
      'operands': [
        {
          'type': 'value',
          'operator': 'equal',
          'lhs': {'type': 'value'},
        },
      ],
    };
    expect(normalizeActivationCondition(group), group);
  });

  testWidgets('state operands include declared and runtime-provided states', (
    tester,
  ) async {
    final registry = DartPluginRegistry()
      ..register(
        DartPluginManifest(
          id: PluginId('sample'),
          name: 'Sample',
          states: const [
            StateSpec<String>(
              id: StateId('online'),
              displayName: 'Online',
              initialValue: 'offline',
            ),
          ],
        ),
      )
      ..updateDynamicState('sample', 'viewerCount', 12);
    final condition = <String, dynamic>{
      'type': 'group',
      'operator': 'and',
      'operands': [
        {
          'type': 'value',
          'id': 'state-check',
          'lhs': {'type': 'state', 'plugin': null, 'state': null},
          'operator': 'equal',
          'rhs': {'type': 'value', 'schemaType': 'String', 'value': ''},
        },
      ],
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 900,
              child: BooleanExpressionEditor(
                value: condition,
                registryFuture: Future.value(registry),
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.decoration.labelText == 'State',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sample - Online'), findsOneWidget);
    expect(find.text('Sample - viewerCount'), findsOneWidget);
  });
}
