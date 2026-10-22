import 'package:flutter/material.dart';
import 'inspector_primitives.dart';
import 'style_values.dart';

class InspectorSection extends StatelessWidget {
  const InspectorSection({
    super.key,
    required this.label,
    required this.child,
    this.trailing,
  });

  final String label;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      border: Border.all(color: Theme.of(context).dividerColor),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: inspectorLabelStyle(context))),
            ?trailing,
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    ),
  );
}

class NullableStyleField extends StatelessWidget {
  const NullableStyleField({
    super.key,
    required this.label,
    required this.present,
    required this.onAdd,
    required this.onRemove,
    required this.child,
  });

  final String label;
  final bool present;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).dividerColor),
      borderRadius: BorderRadius.circular(4),
    ),
    child: present
        ? Row(
            children: [
              SizedBox(
                width: 64,
                child: Text(
                  '$label:',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              Expanded(child: child ?? const SizedBox.shrink()),
              SizedBox(
                width: 28,
                child: IconButton(
                  tooltip: 'Remove $label',
                  onPressed: onRemove,
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.delete,
                    size: 14,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          )
        : InspectorAction(
            icon: Icons.add,
            label: 'Add $label',
            onPressed: onAdd,
          ),
  );
}
