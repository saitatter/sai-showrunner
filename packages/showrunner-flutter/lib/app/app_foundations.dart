import 'package:flutter/material.dart';

import '../design_system/tokens/tokens.dart';

const showRunnerWindowSize = Size(1440, 900);
const showRunnerMinimumWindowSize = Size(1100, 700);

ThemeData buildShowRunnerTheme() {
  final colorScheme =
      ColorScheme.dark(
        primary: ShowRunnerColors.primary,
        onPrimary: ShowRunnerColors.primaryText,
        secondary: ShowRunnerColors.secondary,
        onSecondary: ShowRunnerColors.primaryText,
        surface: ShowRunnerColors.background,
        onSurface: ShowRunnerColors.text,
        error: ShowRunnerColors.error,
        onError: ShowRunnerColors.primaryText,
      ).copyWith(
        surfaceContainerLowest: ShowRunnerColors.surface0,
        surfaceContainerLow: ShowRunnerColors.surfaceB,
        surfaceContainer: ShowRunnerColors.surfaceA,
        surfaceContainerHigh: ShowRunnerColors.surfaceSection,
        surfaceContainerHighest: ShowRunnerColors.surfaceD,
        onSurfaceVariant: ShowRunnerColors.textSecondary,
        outline: ShowRunnerColors.surfaceBorder,
        outlineVariant: ShowRunnerColors.surfaceBorder,
      );
  final controlFill = ShowRunnerColors.surfaceC;

  return ThemeData(
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: ShowRunnerColors.background,
    fontFamily: ShowRunnerTypography.uiFontFamily,
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
    focusColor: colorScheme.primary.withValues(alpha: 0.24),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: controlFill,
      border: const OutlineInputBorder(
        borderSide: BorderSide(color: ShowRunnerColors.surfaceBorder),
      ),
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: ShowRunnerColors.surfaceBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: ShowRunnerColors.surfaceB,
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
