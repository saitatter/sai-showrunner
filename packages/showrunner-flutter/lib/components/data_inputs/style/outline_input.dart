import 'package:flutter/material.dart';
import '../../../schema/data_input.dart';
import 'inspector_section.dart';
import 'schema_field_renderer.dart';
import 'style_values.dart';

class WidgetOutlineStyleInput extends StatelessWidget {
  const WidgetOutlineStyleInput({
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
    final width = styleField(schema, 'width');
    final color = styleField(schema, 'color');
    final style = styleField(schema, 'style');
    return InspectorSection(
      label: schema.label,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (width != null)
            SizedBox(
              width: 92,
              child: SchemaFieldRenderer(
                schema: width,
                value: values['width'],
                onChanged: (next) => onChanged({...values, 'width': next}),
              ),
            ),
          if (width != null && color != null) const SizedBox(width: 8),
          if (color != null)
            Expanded(
              child: SchemaFieldRenderer(
                schema: color,
                value: values['color'],
                onChanged: (next) => onChanged({...values, 'color': next}),
              ),
            ),
          if (style != null) ...[
            const SizedBox(width: 8),
            _OutlineStyleChoice(
              value: values['style']?.toString() ?? 'solid',
              onChanged: (next) => onChanged({...values, 'style': next}),
            ),
          ],
        ],
      ),
    );
  }
}

class _OutlineStyleChoice extends StatelessWidget {
  const _OutlineStyleChoice({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => ToggleButtons(
    constraints: const BoxConstraints(minWidth: 34, minHeight: 40),
    isSelected: [value == 'solid', value == 'dashed', value == 'dotted'],
    onPressed: (index) => onChanged(['solid', 'dashed', 'dotted'][index]),
    children: const [
      Tooltip(message: 'Solid', child: Icon(Icons.horizontal_rule)),
      Tooltip(message: 'Dashed', child: Icon(Icons.more_horiz)),
      Tooltip(message: 'Dotted', child: Icon(Icons.more_vert)),
    ],
  );
}
