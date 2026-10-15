import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/components/data_inputs/numeric_input_formatter.dart';

void main() {
  test('rejects letters, malformed numbers and invalid pasted text', () {
    const formatter = NumericInputFormatter();
    const old = TextEditingValue(
      text: '12',
      selection: TextSelection.collapsed(offset: 2),
    );
    for (final text in [
      'abc',
      '12a',
      'NaN',
      'Infinity',
      '1e5',
      '1.2.3',
      '1-2',
      '12px',
      '12\n',
    ]) {
      expect(
        formatter.formatEditUpdate(old, TextEditingValue(text: text)),
        old,
        reason: text,
      );
    }
    for (final text in ['', '-', '.', '-.', '-12.5', '0.25']) {
      expect(
        formatter.formatEditUpdate(old, TextEditingValue(text: text)).text,
        text,
      );
    }
    const comma = TextEditingValue(
      text: '-12,5',
      selection: TextSelection.collapsed(offset: 5),
    );
    final normalized = formatter.formatEditUpdate(old, comma);
    expect(normalized.text, '-12.5');
    expect(normalized.selection, comma.selection);
  });

  test('integer controls accept only unsigned whole numbers', () {
    const formatter = NumericInputFormatter(decimal: false, signed: false);
    const old = TextEditingValue(text: '255');
    for (final text in ['-1', '2.5', '1,2', 'red']) {
      expect(
        formatter.formatEditUpdate(old, TextEditingValue(text: text)),
        old,
      );
    }
    expect(
      formatter.formatEditUpdate(old, const TextEditingValue(text: '128')).text,
      '128',
    );
  });

  testWidgets('typing or pasting letters keeps the value and caret unchanged', (
    tester,
  ) async {
    final controller = TextEditingController(text: '12');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextField(
            controller: controller,
            inputFormatters: const [NumericInputFormatter()],
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    controller.selection = const TextSelection.collapsed(offset: 2);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '12a',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );
    await tester.pump();
    expect(controller.text, '12');
    expect(controller.selection, const TextSelection.collapsed(offset: 2));
    await tester.enterText(find.byType(TextField), '123abc456');
    expect(controller.text, '12');
    await tester.enterText(find.byType(TextField), '-4,5');
    expect(controller.text, '-4.5');
  });
}
