import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/components/data_inputs/data_input.dart';

void main() {
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
              resourceType: 'BlueSkyAccount',
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
}
