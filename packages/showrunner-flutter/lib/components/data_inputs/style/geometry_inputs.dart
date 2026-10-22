import 'package:flutter/material.dart';
import '../../../schema/data_input.dart';
import '../../../design_system/brand_icons.dart';
import 'inspector_primitives.dart';
import 'inspector_section.dart';
import 'schema_field_renderer.dart';
import 'style_values.dart';

class OverlayBlockStyleInput extends StatelessWidget {
  const OverlayBlockStyleInput({
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
    final margin = styleField(schema, 'margin');
    final padding = styleField(schema, 'padding');
    final horizontal = styleField(schema, 'horizontalAlign');
    final vertical = styleField(schema, 'verticalAlign');

    return InspectorSection(
      label: schema.label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (margin != null && schema.allowMargin != false)
            _edgeGroup(
              margin,
              values['margin'],
              (next) => onChanged({...values, 'margin': next}),
            ),
          if (padding != null && schema.allowPadding != false) ...[
            if (margin != null && schema.allowMargin != false)
              const SizedBox(height: 8),
            _edgeGroup(
              padding,
              values['padding'],
              (next) => onChanged({...values, 'padding': next}),
            ),
          ],
          if (horizontal != null && schema.allowHorizontalAlign != false) ...[
            const SizedBox(height: 10),
            Text('Horizontal alignment', style: inspectorLabelStyle(context)),
            const SizedBox(height: 4),
            InspectorIconChoiceRow(
              selected: values['horizontalAlign']?.toString() ?? 'left',
              choices: [
                ('left', mdiIcon(0xF11C2)),
                ('center', mdiIcon(0xF11C3)),
                ('right', mdiIcon(0xF11C4)),
              ],
              onSelected: (next) =>
                  onChanged({...values, 'horizontalAlign': next}),
            ),
          ],
          if (vertical != null && schema.allowVerticalAlign != false) ...[
            const SizedBox(height: 10),
            Text('Vertical alignment', style: inspectorLabelStyle(context)),
            const SizedBox(height: 4),
            InspectorIconChoiceRow(
              selected: values['verticalAlign']?.toString() ?? 'top',
              choices: [
                ('top', mdiIcon(0xF11C7)),
                ('center', mdiIcon(0xF11C6)),
                ('bottom', mdiIcon(0xF11C5)),
              ],
              onSelected: (next) =>
                  onChanged({...values, 'verticalAlign': next}),
            ),
          ],
        ],
      ),
    );
  }

  Widget _edgeGroup(
    DartDataInputSchema schema,
    dynamic value,
    ValueChanged<dynamic> onChanged,
  ) {
    final values = styleMap(value);
    final fields = [
      styleField(schema, 'top'),
      styleField(schema, 'bottom'),
      styleField(schema, 'left'),
      styleField(schema, 'right'),
    ].whereType<DartDataInputSchema>().toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(schema.label, style: inspectorLabelStyle(null)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final field in fields)
              SizedBox(
                width: 104,
                child: SchemaFieldRenderer(
                  schema: field,
                  value: values[field.key ?? field.label],
                  onChanged: (next) =>
                      onChanged({...values, field.key ?? field.label: next}),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class WidgetBorderRadiusInput extends StatefulWidget {
  const WidgetBorderRadiusInput({
    super.key,
    required this.schema,
    required this.value,
    required this.onChanged,
  });

  final DartDataInputSchema schema;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;

  @override
  State<WidgetBorderRadiusInput> createState() =>
      _WidgetBorderRadiusInputState();
}

class _WidgetBorderRadiusInputState extends State<WidgetBorderRadiusInput> {
  bool _linked = false;

  @override
  Widget build(BuildContext context) {
    final values = styleMap(widget.value);
    final fields = [
      styleField(widget.schema, 'topLeft'),
      styleField(widget.schema, 'topRight'),
      styleField(widget.schema, 'bottomLeft'),
      styleField(widget.schema, 'bottomRight'),
    ].whereType<DartDataInputSchema>().toList();
    if (fields.isEmpty) return const SizedBox.shrink();

    return InspectorSection(
      label: widget.schema.label,
      trailing: IconButton(
        tooltip: _linked ? 'Unlink corners' : 'Link corners',
        onPressed: () => setState(() => _linked = !_linked),
        icon: Icon(_linked ? Icons.link : Icons.link_off, size: 18),
        visualDensity: VisualDensity.compact,
      ),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.7,
        children: [
          for (final field in fields)
            SchemaFieldRenderer(
              schema: field,
              value: values[field.key ?? field.label],
              onChanged: (next) {
                final key = field.key ?? field.label;
                final updated = <String, dynamic>{...values, key: next};
                if (_linked) {
                  for (final other in fields) {
                    updated[other.key ?? other.label] = next;
                  }
                }
                widget.onChanged(updated);
              },
            ),
        ],
      ),
    );
  }
}
