import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/app/app_feedback.dart';
import 'package:showrunner_flutter/app/app_foundations.dart';

void main() {
  testWidgets('feedback is rendered as an overlay without shifting content', (
    tester,
  ) async {
    final contentKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        builder: showRunnerAppFrame,
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                SizedBox(key: contentKey, height: 120, width: 240),
                ElevatedButton(
                  onPressed: () => showShowRunnerFeedback(
                    context,
                    'Created Overlay',
                    severity: ShowRunnerFeedbackSeverity.success,
                  ),
                  child: const Text('Create'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final originalSize = tester.getSize(find.byKey(contentKey));
    await tester.tap(find.text('Create'));
    await tester.pump();

    expect(find.text('Created Overlay'), findsOneWidget);
    expect(find.byType(MaterialBanner), findsNothing);
    expect(tester.getSize(find.byKey(contentKey)), originalSize);
  });

  testWidgets('toast can be dismissed without changing the workspace', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: showRunnerAppFrame,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showShowRunnerFeedback(
                context,
                'Saved project',
                severity: ShowRunnerFeedbackSeverity.success,
              ),
              child: const Text('Save'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Saved project'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.text('Saved project'), findsNothing);
  });
}
