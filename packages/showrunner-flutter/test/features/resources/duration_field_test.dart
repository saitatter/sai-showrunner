import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/resources/duration_field.dart';

void main() {
  test('parses duration text into seconds', () {
    expect(parseDurationSeconds('2h 3m 4s'), 7384);
    expect(parseDurationSeconds('90'), 90);
    expect(parseDurationSeconds('2m 30s'), 150);
    expect(parseDurationSeconds('2m 60s'), isNull);
    expect(parseDurationSeconds('invalid'), isNull);
  });

  testWidgets('emits valid duration input', (tester) async {
    int? seconds;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DurationValueField(
            label: 'Duration',
            initialSeconds: 60,
            onChanged: (value) => seconds = value,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '1m 45s');
    expect(seconds, 105);
  });
}
