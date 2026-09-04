import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/components/data_inputs/data_input.dart';
import 'package:showrunner_flutter/plugins/input/keyboard.dart';

void main() {
  test('maps Flutter logical keys and normalizes combo order', () {
    expect(
      keyboardKeyNameForLogicalKey(LogicalKeyboardKey.keyA),
      'A',
    );
    expect(
      keyboardKeyNameForLogicalKey(LogicalKeyboardKey.controlRight),
      'RightControl',
    );
    expect(
      appendKeyboardKey(['A'], 'RightControl'),
      ['LeftControl', 'A'],
    );
    expect(
      appendKeyboardKey(['LeftControl', 'A'], 'RightControl'),
      ['LeftControl', 'A'],
    );
    expect(keyboardComboDisplayName(['LeftControl', 'A']), 'Control + A');
  });

  testWidgets('captures a single key through the generic data input', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => DartDataInput(
              schema: const DartDataInputSchema(
                label: 'Key',
                kind: DartDataInputKind.keyboardKey,
              ),
              value: selected,
              onChanged: (next) => setState(() => selected = next as String?),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Capture key'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pump();

    expect(selected, 'A');
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('captures a modifier and key as a normalized combo', (
    tester,
  ) async {
    List<String> selected = [];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => DartDataInput(
              schema: const DartDataInputSchema(
                label: 'Shortcut',
                kind: DartDataInputKind.keyCombo,
              ),
              value: selected,
              onChanged: (next) => setState(
                () => selected = List<String>.from(next as List),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Capture key combination'));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlRight);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlRight);
    await tester.pump();

    expect(selected, ['LeftControl', 'A']);
    expect(find.text('Control + A'), findsOneWidget);
  });
}