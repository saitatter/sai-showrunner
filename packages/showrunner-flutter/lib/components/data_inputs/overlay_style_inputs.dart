import 'package:flutter/material.dart';

import '../../features/resources/color_field.dart';
import '../../schema/data_input.dart';

/// Compact editors for the structured overlay styles used by the browser
/// overlay editor. Their layout follows the old inspector: related values are
/// kept together and style objects are edited as one visual group.
class OverlayStyleInput extends StatelessWidget {
  const OverlayStyleInput({
    super.key,
    required this.schema,
    required this.value,
    required this.onChanged,
  });

  final DartDataInputSchema schema;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) => switch (schema.editor) {
    'overlayTextStyle' => _OverlayTextStyleInput(
      schema: schema,
      value: value,
      onChanged: onChanged,
    ),
    'overlayTextAlignment' => _OverlayTextAlignmentInput(
      schema: schema,
      value: value,
      onChanged: onChanged,
    ),
    'overlayBlockStyle' => _OverlayBlockStyleInput(
      schema: schema,
      value: value,
      onChanged: onChanged,
    ),
    'widgetBorderRadius' => _WidgetBorderRadiusInput(
      schema: schema,
      value: value,
      onChanged: onChanged,
    ),
    'widgetBackgroundStyle' => _WidgetBackgroundStyleInput(
      schema: schema,
      value: value,
      onChanged: onChanged,
    ),
    'widgetOutlineStyle' => _WidgetOutlineStyleInput(
      schema: schema,
      value: value,
      onChanged: onChanged,
    ),
    _ => const SizedBox.shrink(),
  };
}

class _OverlayTextStyleInput extends StatelessWidget {
  const _OverlayTextStyleInput({
    required this.schema,
    required this.value,
    required this.onChanged,
  });

  final DartDataInputSchema schema;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    final values = _map(value);
    final family = _field(schema, 'fontFamily');
    final size = _field(schema, 'fontSize');
    final weight = _field(schema, 'fontWeight');
    final color = _field(schema, 'fontColor');
    final stroke = _field(schema, 'stroke');
    final shadow = _field(schema, 'shadow');

    return _InspectorSection(
      label: schema.label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (family != null || size != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (family != null)
                  Expanded(
                    child: _scalar(
                      family,
                      values['fontFamily'],
                      (next) => _set(values, 'fontFamily', next),
                    ),
                  ),
                if (family != null && size != null) const SizedBox(width: 8),
                if (size != null)
                  SizedBox(
                    width: 112,
                    child: _scalar(
                      size,
                      values['fontSize'],
                      (next) => _set(values, 'fontSize', next),
                    ),
                  ),
              ],
            ),
          if (weight != null) ...[
            const SizedBox(height: 8),
            _scalar(
              weight,
              values['fontWeight'],
              (next) => _set(values, 'fontWeight', next),
            ),
          ],
          if (color != null) ...[
            const SizedBox(height: 8),
            _scalar(
              color,
              values['fontColor'],
              (next) => _set(values, 'fontColor', next),
            ),
          ],
          if (stroke != null) ...[
            const SizedBox(height: 10),
            _OptionalStyleSection(
              label: stroke.label,
              present: values['stroke'] is Map,
              onAdd: () =>
                  _set(values, 'stroke', constructDartDataInputDefault(stroke)),
              onRemove: () => _remove(values, 'stroke'),
              child: values['stroke'] is Map
                  ? _StrokeFields(
                      schema: stroke,
                      value: values['stroke'],
                      onChanged: (next) => _set(values, 'stroke', next),
                    )
                  : null,
            ),
          ],
          if (shadow != null) ...[
            const SizedBox(height: 8),
            _OptionalStyleSection(
              label: shadow.label,
              present: values['shadow'] is Map,
              onAdd: () =>
                  _set(values, 'shadow', constructDartDataInputDefault(shadow)),
              onRemove: () => _remove(values, 'shadow'),
              child: values['shadow'] is Map
                  ? _ShadowFields(
                      schema: shadow,
                      value: values['shadow'],
                      onChanged: (next) => _set(values, 'shadow', next),
                    )
                  : null,
            ),
          ],
        ],
      ),
    );
  }

  Widget _scalar(
    DartDataInputSchema field,
    dynamic value,
    ValueChanged<dynamic> onChanged,
  ) => _OverlayScalarField(schema: field, value: value, onChanged: onChanged);

  void _set(Map<String, dynamic> values, String key, dynamic next) =>
      onChanged(<String, dynamic>{...values, key: _clone(next)});

  void _remove(Map<String, dynamic> values, String key) {
    final next = <String, dynamic>{...values}..remove(key);
    onChanged(next);
  }
}

class _StrokeFields extends StatelessWidget {
  const _StrokeFields({
    required this.schema,
    required this.value,
    required this.onChanged,
  });

  final DartDataInputSchema schema;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) => _fieldRow(
    context,
    [_field(schema, 'width'), _field(schema, 'color')],
    value,
    onChanged,
  );
}

class _ShadowFields extends StatelessWidget {
  const _ShadowFields({
    required this.schema,
    required this.value,
    required this.onChanged,
  });

  final DartDataInputSchema schema;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    final values = _map(value);
    return Column(
      children: [
        _fieldRow(
          context,
          [_field(schema, 'blur'), _field(schema, 'color')],
          values,
          (next) => onChanged(next),
        ),
        const SizedBox(height: 8),
        _fieldRow(
          context,
          [_field(schema, 'offsetX'), _field(schema, 'offsetY')],
          values,
          (next) => onChanged(next),
        ),
      ],
    );
  }
}

class _OverlayTextAlignmentInput extends StatelessWidget {
  const _OverlayTextAlignmentInput({
    required this.schema,
    required this.value,
    required this.onChanged,
  });

  final DartDataInputSchema schema;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    final values = _map(value);
    final field = _field(schema, 'textAlign');
    final selected =
        values['textAlign']?.toString() ??
        field?.defaultValue?.toString() ??
        'left';
    if (field == null) return const SizedBox.shrink();

    return _InspectorSection(
      label: schema.label,
      child: _IconChoiceRow(
        selected: selected,
        choices: const [
          ('left', Icons.format_align_left),
          ('center', Icons.format_align_center),
          ('right', Icons.format_align_right),
          ('justify', Icons.format_align_justify),
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
    required this.textAlignmentSchema,
    required this.textAlignment,
    required this.onTextAlignmentChanged,
    required this.blockStyleSchema,
    required this.blockStyle,
    required this.onBlockStyleChanged,
  });

  final DartDataInputSchema textAlignmentSchema;
  final dynamic textAlignment;
  final ValueChanged<dynamic> onTextAlignmentChanged;
  final DartDataInputSchema blockStyleSchema;
  final dynamic blockStyle;
  final ValueChanged<dynamic> onBlockStyleChanged;

  @override
  Widget build(BuildContext context) {
    final textValues = _map(textAlignment);
    final textField = _field(textAlignmentSchema, 'textAlign');
    final blockValues = _map(blockStyle);
    final verticalField = _field(blockStyleSchema, 'verticalAlign');
    if (textField == null || verticalField == null) {
      return const SizedBox.shrink();
    }

    return _InspectorSection(
      label: 'Alignment',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconChoiceRow(
            selected:
                textValues['textAlign']?.toString() ??
                textField.defaultValue?.toString() ??
                'left',
            choices: const [
              ('left', Icons.format_align_left),
              ('center', Icons.format_align_center),
              ('right', Icons.format_align_right),
              ('justify', Icons.format_align_justify),
            ],
            onSelected: (next) =>
                onTextAlignmentChanged({...textValues, 'textAlign': next}),
          ),
          const SizedBox(height: 8),
          _IconChoiceRow(
            selected:
                blockValues['verticalAlign']?.toString() ??
                verticalField.defaultValue?.toString() ??
                'top',
            choices: const [
              ('top', Icons.align_vertical_top),
              ('center', Icons.align_vertical_center),
              ('bottom', Icons.align_vertical_bottom),
            ],
            onSelected: (next) =>
                onBlockStyleChanged({...blockValues, 'verticalAlign': next}),
          ),
        ],
      ),
    );
  }
}

class _OverlayBlockStyleInput extends StatelessWidget {
  const _OverlayBlockStyleInput({
    required this.schema,
    required this.value,
    required this.onChanged,
  });

  final DartDataInputSchema schema;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    final values = _map(value);
    final margin = _field(schema, 'margin');
    final padding = _field(schema, 'padding');
    final horizontal = _field(schema, 'horizontalAlign');
    final vertical = _field(schema, 'verticalAlign');

    return _InspectorSection(
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
            Text('Horizontal alignment', style: _labelStyle(context)),
            const SizedBox(height: 4),
            _IconChoiceRow(
              selected: values['horizontalAlign']?.toString() ?? 'left',
              choices: const [
                ('left', Icons.align_horizontal_left),
                ('center', Icons.align_horizontal_center),
                ('right', Icons.align_horizontal_right),
              ],
              onSelected: (next) =>
                  onChanged({...values, 'horizontalAlign': next}),
            ),
          ],
          if (vertical != null && schema.allowVerticalAlign != false) ...[
            const SizedBox(height: 10),
            Text('Vertical alignment', style: _labelStyle(context)),
            const SizedBox(height: 4),
            _IconChoiceRow(
              selected: values['verticalAlign']?.toString() ?? 'top',
              choices: const [
                ('top', Icons.align_vertical_top),
                ('center', Icons.align_vertical_center),
                ('bottom', Icons.align_vertical_bottom),
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
    final values = _map(value);
    final fields = [
      _field(schema, 'top'),
      _field(schema, 'bottom'),
      _field(schema, 'left'),
      _field(schema, 'right'),
    ].whereType<DartDataInputSchema>().toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(schema.label, style: _labelStyle(null)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final field in fields)
              SizedBox(
                width: 104,
                child: _OverlayScalarField(
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

class _WidgetBorderRadiusInput extends StatefulWidget {
  const _WidgetBorderRadiusInput({
    required this.schema,
    required this.value,
    required this.onChanged,
  });

  final DartDataInputSchema schema;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;

  @override
  State<_WidgetBorderRadiusInput> createState() =>
      _WidgetBorderRadiusInputState();
}

class _WidgetBorderRadiusInputState extends State<_WidgetBorderRadiusInput> {
  bool _linked = false;

  @override
  Widget build(BuildContext context) {
    final values = _map(widget.value);
    final fields = [
      _field(widget.schema, 'topLeft'),
      _field(widget.schema, 'topRight'),
      _field(widget.schema, 'bottomLeft'),
      _field(widget.schema, 'bottomRight'),
    ].whereType<DartDataInputSchema>().toList();
    if (fields.isEmpty) return const SizedBox.shrink();

    return _InspectorSection(
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
            _OverlayScalarField(
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

class _WidgetOutlineStyleInput extends StatelessWidget {
  const _WidgetOutlineStyleInput({
    required this.schema,
    required this.value,
    required this.onChanged,
  });

  final DartDataInputSchema schema;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    final values = _map(value);
    final width = _field(schema, 'width');
    final color = _field(schema, 'color');
    final style = _field(schema, 'style');
    return _InspectorSection(
      label: schema.label,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (width != null)
            SizedBox(
              width: 92,
              child: _OverlayScalarField(
                schema: width,
                value: values['width'],
                onChanged: (next) => onChanged({...values, 'width': next}),
              ),
            ),
          if (width != null && color != null) const SizedBox(width: 8),
          if (color != null)
            Expanded(
              child: _OverlayScalarField(
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

class _WidgetBackgroundStyleInput extends StatelessWidget {
  const _WidgetBackgroundStyleInput({
    required this.schema,
    required this.value,
    required this.onChanged,
  });

  final DartDataInputSchema schema;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    final values = _map(value);
    final color = _field(schema, 'color');
    final layers = _field(schema, 'elements');
    final elements = values['elements'] is List
        ? List<dynamic>.from(values['elements'] as List)
        : <dynamic>[];

    return _InspectorSection(
      label: schema.label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (color != null && values.containsKey('color'))
            _OverlayScalarField(
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
                _SmallAction(
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
                _SmallAction(
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
                _SmallAction(
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
    final values = _map(value);
    final image = _field(schema, 'image');
    final gradient = _field(schema, 'gradient');
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
                ? _GradientFields(
                    schema: gradient,
                    value: values['gradient'],
                    onChanged: (next) =>
                        onChanged({...values, 'gradient': next}),
                  )
                : image != null
                ? _OverlayScalarField(
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

class _GradientFields extends StatelessWidget {
  const _GradientFields({
    required this.schema,
    required this.value,
    required this.onChanged,
  });

  final DartDataInputSchema schema;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    final values = _map(value);
    final type = _field(schema, 'gradientType');
    final angle = _field(schema, 'angle');
    final stopsSchema = _field(schema, 'stops');
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
                child: _OverlayScalarField(
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
                child: _OverlayScalarField(
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
          _SmallAction(
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
    final values = _map(value);
    final color = _field(schema, 'color');
    final position = _field(schema, 'position');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          if (color != null)
            Expanded(
              child: _OverlayScalarField(
                schema: color,
                value: values['color'],
                onChanged: (next) => onChanged({...values, 'color': next}),
              ),
            ),
          if (color != null && position != null) const SizedBox(width: 8),
          if (position != null)
            SizedBox(
              width: 100,
              child: _OverlayScalarField(
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

class _OverlayScalarField extends StatelessWidget {
  const _OverlayScalarField({
    required this.schema,
    required this.value,
    required this.onChanged,
  });

  final DartDataInputSchema schema;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    if (schema.kind == DartDataInputKind.color) {
      return ColorValueField(
        label: schema.label,
        initialValue: value?.toString() ?? '',
        onChanged: onChanged,
      );
    }
    if (schema.kind == DartDataInputKind.boolean) {
      return SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(schema.label),
        value: value == true,
        onChanged: onChanged,
      );
    }
    if (schema.kind == DartDataInputKind.enumeration) {
      return DropdownButtonFormField<String>(
        initialValue: schema.options.contains(value?.toString())
            ? value.toString()
            : null,
        decoration: InputDecoration(labelText: schema.label),
        items: [
          for (final option in schema.options)
            DropdownMenuItem(value: option, child: Text(option)),
        ],
        onChanged: onChanged,
      );
    }
    return _OverlayTextField(
      schema: schema,
      value: value,
      onChanged: (text) => onChanged(
        schema.kind == DartDataInputKind.number
            ? num.tryParse(text.trim()) ?? 0
            : text,
      ),
    );
  }
}

class _OverlayTextField extends StatefulWidget {
  const _OverlayTextField({
    required this.schema,
    required this.value,
    required this.onChanged,
  });

  final DartDataInputSchema schema;
  final dynamic value;
  final ValueChanged<String> onChanged;

  @override
  State<_OverlayTextField> createState() => _OverlayTextFieldState();
}

class _OverlayTextFieldState extends State<_OverlayTextField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _text(widget.value));
  }

  @override
  void didUpdateWidget(covariant _OverlayTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _text(widget.value);
    if (next != _controller.text && !_controller.selection.isValid) {
      _controller.text = next;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    maxLines: widget.schema.kind == DartDataInputKind.multilineText ? 3 : 1,
    keyboardType: widget.schema.kind == DartDataInputKind.number
        ? TextInputType.number
        : TextInputType.text,
    obscureText: widget.schema.secret,
    decoration: InputDecoration(labelText: widget.schema.label),
    onChanged: widget.onChanged,
  );
}

class _InspectorSection extends StatelessWidget {
  const _InspectorSection({
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
            Expanded(child: Text(label, style: _labelStyle(context))),
            ?trailing,
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    ),
  );
}

class _OptionalStyleSection extends StatelessWidget {
  const _OptionalStyleSection({
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
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(label, style: _labelStyle(context))),
                  IconButton(
                    tooltip: 'Remove $label',
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              child ?? const SizedBox.shrink(),
            ],
          )
        : _SmallAction(icon: Icons.add, label: 'Add $label', onPressed: onAdd),
  );
}

class _IconChoiceRow extends StatelessWidget {
  const _IconChoiceRow({
    required this.selected,
    required this.choices,
    required this.onSelected,
  });

  final String selected;
  final List<(String, IconData)> choices;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => ToggleButtons(
    isSelected: [for (final choice in choices) choice.$1 == selected],
    onPressed: (index) => onSelected(choices[index].$1),
    constraints: const BoxConstraints(minWidth: 42, minHeight: 38),
    children: [
      for (final choice in choices)
        Tooltip(
          message: _humanize(choice.$1),
          child: Icon(choice.$2, size: 18),
        ),
    ],
  );
}

class _SmallAction extends StatelessWidget {
  const _SmallAction({
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

Widget _fieldRow(
  BuildContext context,
  List<DartDataInputSchema?> fields,
  dynamic value,
  ValueChanged<dynamic> onChanged,
) {
  final values = _map(value);
  final valid = fields.whereType<DartDataInputSchema>().toList();
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var index = 0; index < valid.length; index++) ...[
        if (index > 0) const SizedBox(width: 8),
        Expanded(
          child: _OverlayScalarField(
            schema: valid[index],
            value: values[valid[index].key ?? valid[index].label],
            onChanged: (next) => onChanged({
              ...values,
              valid[index].key ?? valid[index].label: next,
            }),
          ),
        ),
      ],
    ],
  );
}

DartDataInputSchema? _field(DartDataInputSchema? schema, String key) {
  if (schema == null) return null;
  for (final field in schema.fields) {
    if (field.key == key || field.label == key) return field;
  }
  return null;
}

Map<String, dynamic> _map(dynamic value) => value is Map
    ? {
        for (final entry in value.entries)
          entry.key.toString(): _clone(entry.value),
      }
    : <String, dynamic>{};

dynamic _clone(dynamic value) {
  if (value is Map) return _map(value);
  if (value is List) return value.map(_clone).toList();
  return value;
}

TextStyle? _labelStyle(BuildContext? context) => context == null
    ? null
    : Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600);

String _text(dynamic value) => value?.toString() ?? '';

String _humanize(String value) => value.isEmpty
    ? value
    : '${value[0].toUpperCase()}${value.substring(1).replaceAll('_', ' ')}';
