import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:showrunner_flutter/components/data_inputs/data_input.dart';

void main() {
  test('constructs required schema defaults with runtime field keys', () {
    const schema = DartDataInputSchema(
      label: '',
      kind: DartDataInputKind.object,
      fields: [
        DartDataInputSchema(
          key: 'value',
          label: 'Number',
          kind: DartDataInputKind.number,
          required: true,
        ),
        DartDataInputSchema(
          key: 'fallback',
          label: 'Fallback',
          kind: DartDataInputKind.number,
          defaultValue: 7,
        ),
      ],
    );

    expect(constructDartDataInputDefault(schema), {'value': 0, 'fallback': 7});
  });

  testWidgets('edits fields in an object schema', (tester) async {
    Map<String, dynamic> changed = {};
    const schema = DartDataInputSchema(
      label: 'Scene configuration',
      kind: DartDataInputKind.object,
      fields: [
        DartDataInputSchema(
          key: 'sceneId',
          label: 'Scene',
          kind: DartDataInputKind.text,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DartDataInput(
            schema: schema,
            value: const {'sceneId': 'Intro'},
            onChanged: (value) =>
                changed = Map<String, dynamic>.from(value as Map),
          ),
        ),
      ),
    );

    expect(find.text('Scene'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Main');

    expect(changed, {'sceneId': 'Main'});
  });
}
