import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/remote/remote_dashboard_view.dart';

void main() {
  testWidgets('remote dashboard button keeps a raised front while idle', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 180,
          height: 100,
          child: RemoteDashboardButtonSurface(
            label: 'Start stream',
            color: Colors.red,
          ),
        ),
      ),
    );

    final front = tester.widget<AnimatedPositioned>(
      find.byType(AnimatedPositioned),
    );
    expect(front.top, 0);
    expect(front.bottom, 10);
    expect(find.text('Start stream'), findsNWidgets(2));
  });

  testWidgets('remote dashboard button invokes its RPC when tapped', (
    tester,
  ) async {
    var pressed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 180,
          height: 100,
          child: RemoteDashboardButtonSurface(
            label: 'Start stream',
            color: Colors.red,
            onPressed: () async => pressed++,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(GestureDetector));
    await tester.pumpAndSettle();
    expect(pressed, 1);
    final releasedFront = tester.widget<AnimatedPositioned>(
      find.byType(AnimatedPositioned),
    );
    expect(releasedFront.top, 0);
    expect(releasedFront.bottom, 10);
  });
}
