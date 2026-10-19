import 'package:flutter/material.dart';

import '../tokens/tokens.dart';

class SrPanel extends StatelessWidget {
  const SrPanel({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding ?? const EdgeInsets.all(ShowRunnerSpacing.content),
    decoration: BoxDecoration(
      color: ShowRunnerColors.surfaceCard,
      border: Border.all(color: ShowRunnerColors.surfaceBorder),
      borderRadius: BorderRadius.circular(ShowRunnerSpacing.radius),
    ),
    child: child,
  );
}

class SrButton extends StatelessWidget {
  const SrButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.tooltip,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        fixedSize: const Size.fromHeight(ShowRunnerSpacing.controlHeight),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ShowRunnerSpacing.radius),
        ),
      ),
      child: child,
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

class SrIconButton extends StatelessWidget {
  const SrIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.visualDensity,
    this.iconSize,
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final VisualDensity? visualDensity;
  final double? iconSize;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: icon,
    visualDensity: visualDensity,
    iconSize: iconSize,
  );
}

class SrTextField extends StatelessWidget {
  const SrTextField({
    super.key,
    this.controller,
    this.labelText,
    this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.maxLines = 1,
    this.autofocus = false,
  });

  final TextEditingController? controller;
  final String? labelText;
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final int maxLines;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    autofocus: autofocus,
    maxLines: maxLines,
    onChanged: onChanged,
    onSubmitted: onSubmitted,
    decoration: InputDecoration(labelText: labelText, hintText: hintText),
  );
}

/// A thin draggable divider used between resizable desktop panels.
class SrSplitter extends StatelessWidget {
  const SrSplitter({
    super.key,
    required this.axis,
    required this.onDelta,
    this.onDragEnd,
  });

  /// [Axis.vertical] renders a vertical divider and tracks horizontal drags.
  final Axis axis;
  final ValueChanged<double> onDelta;
  final VoidCallback? onDragEnd;

  @override
  Widget build(BuildContext context) {
    final vertical = axis == Axis.vertical;
    return Semantics(
      label: vertical ? 'Resize sidebar' : 'Resize panel',
      container: true,
      child: MouseRegion(
        cursor: vertical
            ? SystemMouseCursors.resizeColumn
            : SystemMouseCursors.resizeRow,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: vertical
              ? (details) => onDelta(details.primaryDelta ?? 0)
              : null,
          onVerticalDragUpdate: vertical
              ? null
              : (details) => onDelta(details.primaryDelta ?? 0),
          onHorizontalDragEnd: vertical ? (_) => onDragEnd?.call() : null,
          onVerticalDragEnd: vertical ? null : (_) => onDragEnd?.call(),
          child: SizedBox(
            width: vertical ? 8 : double.infinity,
            height: vertical ? double.infinity : 8,
            child: Center(
              child: Container(
                width: vertical ? 1 : double.infinity,
                height: vertical ? double.infinity : 1,
                color: ShowRunnerColors.surfaceBorder,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
