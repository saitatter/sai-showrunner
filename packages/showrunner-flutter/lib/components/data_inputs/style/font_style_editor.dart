import 'package:flutter/material.dart';
import '../../../schema/data_input.dart';
import 'font_family_input.dart';
import 'inspector_section.dart';
import 'schema_field_renderer.dart';
import 'style_values.dart';

class OverlayFontStyleEditor extends StatelessWidget {
  const OverlayFontStyleEditor({
    super.key,
    required this.width,
    required this.schema,
    required this.value,
    required this.onChanged,
    required this.onClose,
  });

  final double width;
  final DartDataInputSchema schema;
  final Map<String, dynamic> value;
  final ValueChanged<dynamic> onChanged;
  final VoidCallback onClose;

  Map<String, dynamic> get _values => styleMap(value);

  void _update(String key, Object? next) {
    final updated = _values;
    if (next == null) {
      updated.remove(key);
    } else {
      updated[key] = cloneStyleValue(next);
    }
    onChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    final family = styleField(schema, 'fontFamily');
    final size = styleField(schema, 'fontSize');
    final color = styleField(schema, 'fontColor');
    final stroke = styleField(schema, 'stroke');
    final shadow = styleField(schema, 'shadow');
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 0,
      color: const Color(0xff202020),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      clipBehavior: Clip.hardEdge,
      child: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: InputDecorationTheme(
            isDense: true,
            filled: true,
            fillColor: const Color(0xff121212),
            floatingLabelBehavior: FloatingLabelBehavior.always,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 10,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: const BorderSide(color: Color(0xff555555)),
            ),
          ),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width, maxHeight: 460),
          child: SizedBox(
            width: width,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      height: 20,
                      child: IconButton(
                        key: const ValueKey('overlay-font-editor-close'),
                        tooltip: 'Close font editor',
                        padding: EdgeInsets.zero,
                        onPressed: onClose,
                        icon: const Icon(Icons.close, size: 14),
                      ),
                    ),
                  ),
                  if (family != null || size != null)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (family != null)
                          Expanded(
                            child: OverlayFontFamilyInput(
                              label: family.label,
                              value: _values['fontFamily']?.toString() ?? '',
                              onChanged: (next) => _update('fontFamily', next),
                            ),
                          ),
                        if (family != null && size != null)
                          const SizedBox(width: 8),
                        if (size != null)
                          SizedBox(
                            width: (width - 32) / 2,
                            child: SchemaFieldRenderer(
                              schema: size,
                              compact: true,
                              value: _values['fontSize'],
                              onChanged: (next) => _update('fontSize', next),
                            ),
                          ),
                      ],
                    ),
                  if (color != null) ...[
                    const SizedBox(height: 8),
                    SchemaFieldRenderer(
                      schema: color,
                      compact: true,
                      value: _values['fontColor'],
                      onChanged: (next) => _update('fontColor', next),
                    ),
                  ],
                  if (stroke != null) ...[
                    const SizedBox(height: 10),
                    NullableStyleField(
                      label: stroke.label,
                      present: _values['stroke'] is Map,
                      onAdd: () {
                        final defaults = styleMap(
                          constructDartDataInputDefault(stroke),
                        );
                        defaults['width'] = 3;
                        defaults['color'] ??= '#000000';
                        _update('stroke', defaults);
                      },
                      onRemove: () => _update('stroke', null),
                      child: _values['stroke'] is Map
                          ? _StrokeFields(
                              schema: stroke,
                              value: _values['stroke'],
                              onChanged: (next) => _update('stroke', next),
                            )
                          : null,
                    ),
                  ],
                  if (shadow != null) ...[
                    const SizedBox(height: 8),
                    NullableStyleField(
                      label: shadow.label,
                      present: _values['shadow'] is Map,
                      onAdd: () => _update('shadow', {
                        ...styleMap(constructDartDataInputDefault(shadow)),
                        'blur': 4,
                        'color': '#FFFFFF',
                        'offsetX': 0,
                        'offsetY': 0,
                      }),
                      onRemove: () => _update('shadow', null),
                      child: _values['shadow'] is Map
                          ? _ShadowFields(
                              schema: shadow,
                              value: _values['shadow'],
                              onChanged: (next) => _update('shadow', next),
                            )
                          : null,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
  Widget build(BuildContext context) => styleFieldRow(
    context,
    [styleField(schema, 'width'), styleField(schema, 'color')],
    value,
    onChanged,
    compact: true,
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
    final values = styleMap(value);
    return Column(
      children: [
        styleFieldRow(
          context,
          [styleField(schema, 'blur'), styleField(schema, 'color')],
          values,
          (next) => onChanged(next),
          compact: true,
        ),
        const SizedBox(height: 8),
        styleFieldRow(
          context,
          [styleField(schema, 'offsetX'), styleField(schema, 'offsetY')],
          values,
          (next) => onChanged(next),
          compact: true,
        ),
      ],
    );
  }
}
