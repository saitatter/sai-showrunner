import 'package:flutter/material.dart';

const showRunnerWindowSize = Size(1440, 900);
const showRunnerMinimumWindowSize = Size(1100, 700);

ThemeData buildShowRunnerTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xff2dd4bf),
    brightness: Brightness.dark,
  );
  final controlFill = colorScheme.surfaceContainerHighest.withValues(
    alpha: 0.38,
  );

  return ThemeData(
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: const Color(0xff101416),
    fontFamily: 'Segoe UI',
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
    focusColor: colorScheme.primary.withValues(alpha: 0.24),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: controlFill,
      border: const OutlineInputBorder(),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: colorScheme.surfaceContainer,
      selectedIconTheme: IconThemeData(color: colorScheme.primary),
      selectedLabelTextStyle: TextStyle(color: colorScheme.primary),
      indicatorColor: colorScheme.primaryContainer,
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 450),
    ),
  );
}

Widget showRunnerAppFrame(BuildContext context, Widget? child) {
  return Semantics(
    container: true,
    label: 'ShowRunner desktop application',
    child: FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: FocusScope(
        autofocus: true,
        child: child ?? const SizedBox.shrink(),
      ),
    ),
  );
}
