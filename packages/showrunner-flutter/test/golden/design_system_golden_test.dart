import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/app/app_foundations.dart';
import 'package:showrunner_flutter/design_system/controls/controls.dart';
import 'package:showrunner_flutter/design_system/tokens/tokens.dart';

void main() {
  testWidgets('renders the shared controls at the desktop baseline', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 180);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildShowRunnerTheme(),
        home: SizedBox(
          key: const ValueKey('design-system-baseline'),
          width: 360,
          height: 180,
          child: Material(
            color: ShowRunnerColors.background,
            child: Padding(
              padding: const EdgeInsets.all(ShowRunnerSpacing.content),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const SrButton(
                        onPressed: null,
                        child: Text('Save'),
                      ),
                      const SizedBox(width: ShowRunnerSpacing.inline),
                      SrIconButton(
                        tooltip: 'Copy',
                        onPressed: () {},
                        icon: const Icon(Icons.copy),
                      ),
                    ],
                  ),
                  const SizedBox(height: ShowRunnerSpacing.inline),
                  const SrTextField(labelText: 'Automation name'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await expectLater(
      find.byKey(const ValueKey('design-system-baseline')),
      matchesGoldenFile('goldens/design_system_controls.png'),
    );
  });
}
