import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/obs/transform.dart';
import 'package:showrunner_flutter/plugins/obs/ui/obs_transform_input.dart';

void main() {
  test('converts the nested transform model to OBS WebSocket fields', () {
    final payload = obsTransformToWebSocket({
      'position': {'x': 100, 'y': 50},
      'rotation': 15,
      'scale': {'x': 2, 'y': 1},
      'crop': {'top': 1, 'right': 2, 'bottom': 3, 'left': 4},
      'alignment': 5,
      'boundingBox': {
        'alignment': 10,
        'boxType': 'OBS_BOUNDS_STRETCH',
        'width': 0,
        'height': 720,
      },
    });

    expect(payload, {
      'positionX': 100,
      'positionY': 50,
      'rotation': 15,
      'alignment': 5,
      'scaleX': 2,
      'scaleY': 1,
      'cropTop': 1,
      'cropRight': 2,
      'cropBottom': 3,
      'cropLeft': 4,
      'boundsAlignment': 10,
      'boundsType': 'OBS_BOUNDS_STRETCH',
      'boundsWidth': 1,
      'boundsHeight': 720,
    });
  });

  testWidgets('shows transform groups and links scale axes', (tester) async {
    Map<String, dynamic> value = {
      'scale': {'x': 2, 'y': 1},
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setState) => ObsTransformInput(
                label: 'Transform',
                value: value,
                onChanged: (next) => setState(() => value = next),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Position'), findsOneWidget);
    expect(find.text('Size'), findsOneWidget);
    expect(find.text('Crop'), findsOneWidget);
    expect(find.text('Bounds'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsOneWidget);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(3), '4');
    await tester.pump();

    expect(value['scale'], {'x': 4, 'y': 2});
  });
}