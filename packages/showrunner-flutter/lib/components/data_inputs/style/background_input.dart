import 'package:flutter/material.dart';
import '../../../schema/data_input.dart';
import 'gradient_fields.dart';
import 'inspector_primitives.dart';
import 'inspector_section.dart';
import 'schema_field_renderer.dart';
import 'style_values.dart';

class WidgetBackgroundStyleInput extends StatelessWidget {
  const WidgetBackgroundStyleInput({
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
    final color = styleField(schema, 'color');
    final layers = styleField(schema, 'elements');
    final elements = values['elements'] is List
        ? List<dynamic>.from(values['elements'] as List)
        : <dynamic>[];

    return InspectorSection(
      label: schema.label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (color != null && values.containsKey('color'))
            SchemaFieldRenderer(
              schema: color,
              value: values['color'],
              onChanged: (next) => onChanged({...values, 'color': next}),
            ),
          if (layers != null && elements.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (var index = 0; index < elements.length; index++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _BackgroundLayer(
                  value: elements[index],
                  schema: layers.itemSchema,
                  onChanged: (next) {
                    final updated = [...elements];
                    updated[index] = next;
                    onChanged({...values, 'elements': updated});
                  },
                  onDelete: () {
                    final updated = [...elements]..removeAt(index);
                    onChanged({...values, 'elements': updated});
                  },
                ),
              ),
          ],
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            children: [
              if (color != null)
                InspectorAction(
                  icon: Icons.format_color_fill,
                  label: values.containsKey('color')
                      ? 'Remove color'
                      : 'Add color',
                  onPressed: () {
                    final updated = <String, dynamic>{...values};
                    if (updated.containsKey('color')) {
                      updated.remove('color');
                    } else {
                      updated['color'] = color.defaultValue ?? '#FFFFFF';
                    }
                    onChanged(updated);
                  },
                ),
              if (layers != null)
                InspectorAction(
                  icon: Icons.gradient,
                  label: 'Add gradient',
                  onPressed: () {
                    onChanged({
                      ...values,
                      'elements': [
                        {
                          'gradient': {
                            'gradientType': 'linear',
                            'angle': 0,
                            'stops': [
                              {'color': '#FF00DC', 'position': 0},
                              {'color': '#00FFFF', 'position': 1},
                            ],
                          },
                        },
                        ...elements,
                      ],
                    });
                  },
                ),
              if (layers != null)
                InspectorAction(
                  icon: Icons.image_outlined,
                  label: 'Add image',
                  onPressed: () => onChanged({
                    ...values,
                    'elements': [
                      {'image': ''},
                      ...elements,
                    ],
                  }),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BackgroundLayer extends StatelessWidget {
  const _BackgroundLayer({
    required this.value,
    required this.schema,
    required this.onChanged,
    required this.onDelete,
  });

  final dynamic value;
  final DartDataInputSchema? schema;
  final ValueChanged<dynamic> onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final values = styleMap(value);
    final image = styleField(schema, 'image');
    final gradient = styleField(schema, 'gradient');
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: values['gradient'] is Map && gradient != null
                ? OverlayGradientFields(
                    schema: gradient,
                    value: values['gradient'],
                    onChanged: (next) =>
                        onChanged({...values, 'gradient': next}),
                  )
                : image != null
                ? SchemaFieldRenderer(
                    schema: image,
                    value: values['image'],
                    onChanged: (next) => onChanged({...values, 'image': next}),
                  )
                : Text(values.toString()),
          ),
          IconButton(
            tooltip: 'Remove layer',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
