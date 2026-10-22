import 'package:flutter/material.dart';
import '../../../schema/data_input.dart';
import '../../../design_system/brand_icons.dart';
import 'inspector_primitives.dart';
import 'inspector_section.dart';
import 'style_values.dart';

class OverlayTextAlignmentInput extends StatelessWidget {
  const OverlayTextAlignmentInput({
    super.key,
    required this.schema,
    required this.value,
    required this.onChanged,
  });

  final DartDataInputSchema schema;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    final values = styleMap(value);
    final field = styleField(schema, 'textAlign');
    final selected =
        values['textAlign']?.toString() ??
        field?.defaultValue?.toString() ??
        'left';
    if (field == null) return const SizedBox.shrink();

    return InspectorSection(
      label: schema.label,
      child: InspectorIconChoiceRow(
        selected: selected,
        choices: const [
          ('left', IconData(0xF0262, fontFamily: 'Material Design Icons')),
          ('center', IconData(0xF0260, fontFamily: 'Material Design Icons')),
          ('right', IconData(0xF0263, fontFamily: 'Material Design Icons')),
          ('justify', IconData(0xF0261, fontFamily: 'Material Design Icons')),
        ],
        onSelected: (next) => onChanged({...values, 'textAlign': next}),
      ),
    );
  }
}

/// Presents the text and vertical alignment controls together, matching the
/// two-row alignment editor used by the overlay widget inspector.
class OverlayLabelAlignmentInput extends StatelessWidget {
  const OverlayLabelAlignmentInput({
    super.key,
    this.showLabels = true,
    required this.textAlignmentSchema,
    required this.textAlignment,
    required this.onTextAlignmentChanged,
    required this.blockStyleSchema,
    required this.blockStyle,
    required this.onBlockStyleChanged,
  });

  final bool showLabels;
  final DartDataInputSchema textAlignmentSchema;
  final dynamic textAlignment;
  final ValueChanged<dynamic> onTextAlignmentChanged;
  final DartDataInputSchema blockStyleSchema;
  final dynamic blockStyle;
  final ValueChanged<dynamic> onBlockStyleChanged;

  @override
  Widget build(BuildContext context) {
    final textValues = styleMap(textAlignment);
    final textField = styleField(textAlignmentSchema, 'textAlign');
    final blockValues = styleMap(blockStyle);
    final verticalField = styleField(blockStyleSchema, 'verticalAlign');
    if (textField == null || verticalField == null) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          key: const ValueKey('overlay-label-horizontal-alignment-row'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showLabels)
                _alignmentGroupLabel(context, textAlignmentSchema.label),
              const SizedBox(height: 4),
              InspectorIconChoiceRow(
                selected:
                    textValues['textAlign']?.toString() ??
                    textField.defaultValue?.toString() ??
                    'left',
                choices: [
                  ('left', mdiIcon(0xF0262)),
                  ('center', mdiIcon(0xF0260)),
                  ('right', mdiIcon(0xF0263)),
                  ('justify', mdiIcon(0xF0261)),
                ],
                onSelected: (next) =>
                    onTextAlignmentChanged({...textValues, 'textAlign': next}),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Center(
          key: const ValueKey('overlay-label-vertical-alignment-row'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showLabels)
                _alignmentGroupLabel(context, blockStyleSchema.label),
              const SizedBox(height: 4),
              InspectorIconChoiceRow(
                selected:
                    blockValues['verticalAlign']?.toString() ??
                    verticalField.defaultValue?.toString() ??
                    'top',
                choices: [
                  ('top', mdiIcon(0xF11C7)),
                  ('center', mdiIcon(0xF11C6)),
                  ('bottom', mdiIcon(0xF11C5)),
                ],
                onSelected: (next) => onBlockStyleChanged({
                  ...blockValues,
                  'verticalAlign': next,
                }),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _alignmentGroupLabel(BuildContext context, String label) => Align(
    alignment: Alignment.centerLeft,
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
