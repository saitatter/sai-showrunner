import 'package:flutter/material.dart';
import 'style_values.dart';

class InspectorIconChoiceRow extends StatelessWidget {
  const InspectorIconChoiceRow({
    super.key,
    required this.selected,
    required this.choices,
    required this.onSelected,
  });

  final String selected;
  final List<(String, IconData)> choices;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xff111111),
        borderRadius: BorderRadius.circular(6),
      ),
      child: ToggleButtons(
        isSelected: [for (final choice in choices) choice.$1 == selected],
        onPressed: (index) => onSelected(choices[index].$1),
        constraints: const BoxConstraints(minWidth: 44, minHeight: 26),
        renderBorder: false,
        borderRadius: BorderRadius.circular(4),
        borderColor: colors.outlineVariant,
        selectedBorderColor: colors.primary,
        color: colors.onSurfaceVariant,
        selectedColor: colors.onSurface,
        fillColor: const Color(0xff3c3c3c),
        children: [
          for (final choice in choices)
            Tooltip(
              message: humanizeStyleChoice(choice.$1),
              child: Icon(choice.$2, size: 18),
            ),
        ],
      ),
    );
  }
}

class InspectorAction extends StatelessWidget {
  const InspectorAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: 16),
    label: Text(label),
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      visualDensity: VisualDensity.compact,
    ),
  );
}
