import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/app/app_foundations.dart';
import 'package:showrunner_flutter/design_system/tokens/tokens.dart';

void main() {
  test('defines a desktop-sized window with a usable minimum', () {
    expect(
      showRunnerWindowSize.width,
      greaterThan(showRunnerMinimumWindowSize.width),
    );
    expect(
      showRunnerWindowSize.height,
      greaterThan(showRunnerMinimumWindowSize.height),
    );
  });

  test('builds the shared dark theme with accessible controls', () {
    final theme = buildShowRunnerTheme();

    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.primary, ShowRunnerColors.primary);
    expect(theme.scaffoldBackgroundColor, ShowRunnerColors.background);
    expect(
      theme.textTheme.bodyMedium?.fontFamily,
      ShowRunnerTypography.uiFontFamily,
    );
    expect(theme.inputDecorationTheme.filled, isTrue);
    expect(theme.navigationRailTheme.indicatorColor, isNotNull);
    expect(theme.tooltipTheme.waitDuration, const Duration(milliseconds: 450));
  });

  testWidgets('exposes an application semantic root and tab traversal', (
    tester,
  ) async {
    final firstFocus = FocusNode(debugLabel: 'first control');
    final secondFocus = FocusNode(debugLabel: 'second control');
    addTearDown(firstFocus.dispose);
    addTearDown(secondFocus.dispose);

    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        builder: showRunnerAppFrame,
        home: Row(
          children: [
            FocusTraversalOrder(
              order: const NumericFocusOrder(1),
              child: Focus(
                focusNode: firstFocus,
                child: const IconButton(
                  onPressed: null,
                  tooltip: 'First control',
                  icon: Icon(Icons.circle),
                ),
              ),
            ),
            FocusTraversalOrder(
              order: const NumericFocusOrder(2),
              child: Focus(
                focusNode: secondFocus,
                child: const IconButton(
                  onPressed: null,
                  tooltip: 'Second control',
                  icon: Icon(Icons.square),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    expect(
      find.bySemanticsLabel('ShowRunner desktop application'),
      findsOneWidget,
    );

    firstFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(secondFocus.hasFocus, isTrue);
    semantics.dispose();
  });
}
