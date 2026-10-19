import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/resources/color_field.dart';
import 'package:showrunner_flutter/features/resources/color_picker.dart';

void main() {
  test('CSS alpha colors round trip in RGBA order', () {
    final color = parseCssColor('#ff000080')!;
    expect(color.toARGB32(), 0x80ff0000);
    expect(cssColorHex(color), '#ff000080');
    expect(parseCssColor('not-a-color'), isNull);
  });

  testWidgets('wheel, RGB, HSV, alpha and hex stay synchronized', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 402,
            child: ShowRunnerColorPicker(
              initialValue: '#ffffff',
              onChanged: (value) => selected = value,
              onPaletteSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    final wheel = find.byKey(const ValueKey('color-wheel'));
    final rect = tester.getRect(wheel);
    await tester.tapAt(Offset(rect.center.dx, rect.top + 1));
    await tester.pump();
    expect(parseCssColor(selected!)!.r, greaterThan(.95));
    expect(parseCssColor(selected!)!.g, lessThan(.03));
    await tester.enterText(
      find.byKey(const ValueKey('color-channel-H')),
      '120',
    );
    await tester.pump();
    expect(parseCssColor(selected!)!.g, greaterThan(.95));
    await tester.enterText(
      find.byKey(const ValueKey('color-channel-A')),
      '128',
    );
    await tester.pump();
    expect(parseCssColor(selected!)!.toARGB32() >> 24, 128);
    await tester.enterText(find.byKey(const ValueKey('color-hex')), '12345680');
    await tester.pump();
    expect(selected, '#12345680');
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('color-channel-R')))
          .controller!
          .text,
      '18',
    );
    await tester.enterText(find.byKey(const ValueKey('color-hex')), 'invalid');
    await tester.pump();
    expect(selected, '#12345680');
    await tester.enterText(
      find.byKey(const ValueKey('color-channel-R')),
      '255',
    );
    await tester.pump();
    expect(selected, '#ff345680');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'color popover updates live and stays usable when host disappears',
    (tester) async {
      String? selected;
      final showHost = ValueNotifier(true);
      addTearDown(showHost.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: showHost,
              builder: (context, visible, _) => visible
                  ? ColorValueField(
                      label: 'Shadow Color',
                      initialValue: '#ffffff',
                      bar: true,
                      onChanged: (value) => selected = value,
                    )
                  : const SizedBox(),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(InputDecorator));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('color-hex')),
        'ff000080',
      );
      await tester.pump();
      expect(selected, '#ff000080');
      expect(
        find.byKey(const ValueKey('color-picker-popover')),
        findsOneWidget,
      );
      showHost.value = false;
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('color-channel-A')),
        '0',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('#ffffff'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
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
    expect(find.byKey(const ValueKey('color-wheel')), findsOneWidget);
    await tester.tap(find.byTooltip('#ef4444'));
    await tester.pump();

    expect(selected, '#ef4444');
    expect(find.text('#ef4444'), findsOneWidget);
  });
}
