import 'package:flutter/material.dart';
import '../../../schema/data_input.dart';

DartDataInputSchema? styleField(DartDataInputSchema? schema, String key) {
  if (schema == null) return null;
  for (final field in schema.fields) {
    if (field.key == key || field.label == key) return field;
  }
  return null;
}

Map<String, dynamic> styleMap(dynamic value) => value is Map
    ? {
        for (final entry in value.entries)
          entry.key.toString(): cloneStyleValue(entry.value),
      }
    : <String, dynamic>{};

dynamic cloneStyleValue(dynamic value) {
  if (value is Map) return styleMap(value);
  if (value is List) return value.map(cloneStyleValue).toList();
  return value;
}

TextStyle? inspectorLabelStyle(BuildContext? context) => context == null
    ? null
    : Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600);

String styleText(dynamic value) => value?.toString() ?? '';

String humanizeStyleChoice(String value) => value.isEmpty
    ? value
    : '${value[0].toUpperCase()}${value.substring(1).replaceAll('_', ' ')}';

/// Retains the existing numeric fallback while the field owns partial text.
Object parseStyleScalar(DartDataInputSchema schema, String text) =>
    schema.kind == DartDataInputKind.number
    ? num.tryParse(text.trim()) ?? 0
    : text;
