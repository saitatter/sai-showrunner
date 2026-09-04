import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/iot/light_color.dart';
import 'package:showrunner_flutter/plugins/iot/ui/light_color_input.dart';

void main() {
  test('preserves the legacy HSB and Kelvin color formats', () {
    final hsb = parseLightColor('hsb(120, 50, 80)');
    final kelvin = parseLightColor('kb(4200, 65)');

    expect(hsb?.hue, 120);
    expect(serializeLightColor(hsb!), 'hsb(120, 50, 80)');
    expect(kelvin?.kelvin, 4200);
    expect(serializeLightColor(kelvin!), 'kb(4200, 65)');
    expect(parseLightColor('rgb(255, 0, 0)'), isNull);
  });

  test('updates brightness and clamps Kelvin to the legacy device range', () {
    expect(
      serializeLightColor(lightColorForBrightness('kb(4200, 65)', 20)),
      'kb(4200, 20)',
    );
    expect(
      lightColorForKelvin(null, 1000).kelvin,
      lightColorMinKelvin,
    );
    expect(
      lightColorForKelvin(null, 9000).kelvin,
      lightColorMaxKelvin,
    );
    expect(lightColorPreview('hsb(0, 100, 100)'), isA<Color>());
  });

  testWidgets('picker exposes RGB and CCT controls and emits Kelvin values', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => LightColorInput(
              label: 'Color',
              value: selected,
              onChanged: (next) => setState(() => selected = next),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Choose light color'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('RGB'), findsOneWidget);
    expect(find.text('CCT'), findsOneWidget);
    expect(find.byType(LightColorWheel), findsOneWidget);
    expect(find.byType(LightBrightnessSlider), findsOneWidget);

    await tester.tap(find.text('CCT'));
    await tester.pump();
    expect(find.byType(LightTemperatureSlider), findsOneWidget);
    await tester.drag(find.byType(LightTemperatureSlider), const Offset(0, 24));
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pump();

    expect(selected, startsWith('kb('));
  });
}