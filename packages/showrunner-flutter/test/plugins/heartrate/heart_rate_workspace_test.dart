import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/heartrate/ble/fake_transport.dart';
import 'package:showrunner_flutter/plugins/heartrate/services/heart_rate_service.dart';
import 'package:showrunner_flutter/plugins/heartrate/ui/heart_rate_workspace.dart';

void main() {
  testWidgets('renders live monitoring, history, zones, and simulation', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1440, 1100)
      ..devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final transport = FakeBleTransport(
      emitMeasurements: false,
      measurementInterval: const Duration(hours: 1),
    );
    final service = HeartRateService(transport: transport);
    addTearDown(service.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: HeartRateWorkspace(service: service)),
      ),
    );

    expect(find.text('Heart Rate'), findsOneWidget);
    expect(find.text('Heart-rate history'), findsOneWidget);
    expect(find.text('Zones'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -1000));
    await tester.pump();
    expect(find.text('Start H808S simulation'), findsOneWidget);
    expect(find.text('Waiting for heart-rate data.'), findsOneWidget);

    await service.startSimulation(bpm: 142, batteryPercent: 75);
    await tester.pump();
    transport.lastConnection!.emitHeartRate(142);
    await tester.pump();

    expect(find.text('142'), findsWidgets);
    expect(find.text('Reset statistics'), findsOneWidget);
    expect(find.text('Save zones'), findsOneWidget);

    await service.close();
  });
}
