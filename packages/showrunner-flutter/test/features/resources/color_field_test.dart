import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/resources/color_field.dart';

void main() {
  testWidgets('selects a palette color and emits its hex value', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ColorValueField(
            label: 'Color',
            initialValue: '#ffffff',
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Choose color'));
    await tester.pumpAndSettle();
    expect(find.text('Color'), findsNWidgets(2));
    await tester.tap(find.byTooltip('#ef4444'));
    await tester.pump();

    expect(selected, '#ef4444');
    expect(find.text('#ef4444'), findsOneWidget);
  });
}
