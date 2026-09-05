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
