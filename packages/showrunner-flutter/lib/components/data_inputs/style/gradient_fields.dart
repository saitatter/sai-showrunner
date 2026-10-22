import 'package:flutter/material.dart';
import '../../../schema/data_input.dart';
import 'inspector_primitives.dart';
import 'schema_field_renderer.dart';
import 'style_values.dart';

class OverlayGradientFields extends StatelessWidget {
  const OverlayGradientFields({
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
    final type = styleField(schema, 'gradientType');
    final angle = styleField(schema, 'angle');
    final stopsSchema = styleField(schema, 'stops');
    final stops = values['stops'] is List
        ? List<dynamic>.from(values['stops'] as List)
        : <dynamic>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (type != null)
              Expanded(
                child: SchemaFieldRenderer(
                  schema: type,
                  value: values['gradientType'],
                  onChanged: (next) =>
                      onChanged({...values, 'gradientType': next}),
                ),
              ),
            if (type != null && angle != null) const SizedBox(width: 8),
            if (angle != null)
              SizedBox(
                width: 100,
                child: SchemaFieldRenderer(
                  schema: angle,
                  value: values['angle'],
                  onChanged: (next) => onChanged({...values, 'angle': next}),
                ),
              ),
          ],
        ),
        if (stopsSchema != null) ...[
          const SizedBox(height: 6),
          for (var index = 0; index < stops.length; index++)
            _GradientStop(
              schema: stopsSchema.itemSchema,
              value: stops[index],
              onChanged: (next) {
                final updated = [...stops];
                updated[index] = next;
                onChanged({...values, 'stops': updated});
              },
              onDelete: () {
                final updated = [...stops]..removeAt(index);
                onChanged({...values, 'stops': updated});
              },
            ),
          InspectorAction(
            icon: Icons.add,
            label: 'Add stop',
            onPressed: () => onChanged({
              ...values,
              'stops': [
                ...stops,
                {'color': '#FFFFFF', 'position': 1},
              ],
            }),
          ),
        ],
      ],
    );
  }
}

class _GradientStop extends StatelessWidget {
  const _GradientStop({
    required this.schema,
    required this.value,
    required this.onChanged,
    required this.onDelete,
  });

  final DartDataInputSchema? schema;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final values = styleMap(value);
    final color = styleField(schema, 'color');
    final position = styleField(schema, 'position');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          if (color != null)
            Expanded(
              child: SchemaFieldRenderer(
                schema: color,
                value: values['color'],
                onChanged: (next) => onChanged({...values, 'color': next}),
              ),
            ),
          if (color != null && position != null) const SizedBox(width: 8),
          if (position != null)
            SizedBox(
              width: 100,
              child: SchemaFieldRenderer(
                schema: position,
                value: values['position'],
                onChanged: (next) => onChanged({...values, 'position': next}),
              ),
            ),
          IconButton(
            tooltip: 'Remove stop',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
