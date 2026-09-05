import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/app/app_foundations.dart';
import 'package:showrunner_flutter/design_system/controls/controls.dart';
import 'package:showrunner_flutter/design_system/tokens/tokens.dart';

void main() {
  testWidgets('uses ShowRunner control metrics and semantics', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildShowRunnerTheme(),
        home: const Scaffold(
          body: Column(
            children: [
              SrButton(onPressed: null, child: Text('Save')),
              SrIconButton(
                tooltip: 'Copy selected nodes',
                onPressed: null,
                icon: Icon(Icons.copy),
              ),
              SrTextField(labelText: 'Name'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Save'), findsOneWidget);
    expect(find.byTooltip('Copy selected nodes'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.getSize(find.byType(SrButton)).height,
      ShowRunnerSpacing.controlHeight,
    );
  });
}
