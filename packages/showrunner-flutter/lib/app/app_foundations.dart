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
  final textTheme = _scaledTextTheme(
    ThemeData.dark(useMaterial3: true).textTheme,
  );

  return ThemeData(
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: ShowRunnerColors.background,
    fontFamily: ShowRunnerTypography.uiFontFamily,
    textTheme: textTheme,
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
    focusColor: colorScheme.primary.withValues(alpha: 0.24),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    ),
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

TextTheme _scaledTextTheme(TextTheme base) => TextTheme(
  displayLarge: _scaleTextStyle(base.displayLarge),
  displayMedium: _scaleTextStyle(base.displayMedium),
  displaySmall: _scaleTextStyle(base.displaySmall),
  headlineLarge: _scaleTextStyle(base.headlineLarge),
  headlineMedium: _scaleTextStyle(base.headlineMedium),
  headlineSmall: _scaleTextStyle(base.headlineSmall),
  titleLarge: _scaleTextStyle(base.titleLarge),
  titleMedium: _scaleTextStyle(base.titleMedium),
  titleSmall: _scaleTextStyle(base.titleSmall),
  bodyLarge: _scaleTextStyle(base.bodyLarge),
  bodyMedium: _scaleTextStyle(base.bodyMedium),
  bodySmall: _scaleTextStyle(base.bodySmall),
  labelLarge: _scaleTextStyle(base.labelLarge),
  labelMedium: _scaleTextStyle(base.labelMedium),
  labelSmall: _scaleTextStyle(base.labelSmall),
);

TextStyle? _scaleTextStyle(TextStyle? style) {
  if (style == null) return null;
  final fontSize = style.fontSize;
  return style.copyWith(
    fontFamily: ShowRunnerTypography.uiFontFamily,
    fontSize: fontSize == null ? null : fontSize * 1.06,
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
