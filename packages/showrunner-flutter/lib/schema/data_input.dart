/// Flutter-free data input contracts used by plugin manifests and schemas.
library;

import 'identifiers.dart';

enum DartDataInputKind {
  text,
  multilineText,
  number,
  boolean,
  enumeration,
  color,
  duration,
  lightColor,
  obsTransform,
  keyboardKey,
  keyCombo,
  array,
  object,
  filePath,
  resource,
}

final class DartDataInputSchema {
  const DartDataInputSchema({
    required this.label,
    required this.kind,
    this.key,
    this.options = const <String>[],
    this.required = false,
    this.secret = false,
    this.multiline = false,
    this.defaultValue,
    this.resourceType,
    this.fields = const <DartDataInputSchema>[],
    this.itemKind = DartDataInputKind.text,
    this.itemSchema,
    this.editor,
    this.allowMargin,
    this.allowPadding,
    this.allowHorizontalAlign,
    this.allowVerticalAlign,
  });

  final String label;
  final DartDataInputKind kind;
  final String? key;
  final List<String> options;
  final bool required;
  final bool secret;
  final bool multiline;

  /// A schema default is metadata, not an untyped runtime callback value.
  ///
  /// The value can still be a JSON-shaped map/list because schemas describe
  /// nested inputs, but keeping the public contract as [Object?] prevents
  /// `dynamic` from leaking through plugin manifests. Decoding into the
  /// runtime map remains an explicit boundary in the construction helpers.
  final Object? defaultValue;
  final ResourceTypeId? resourceType;
  final List<DartDataInputSchema> fields;
  final DartDataInputKind itemKind;
  final DartDataInputSchema? itemSchema;

  /// Optional renderer supplied by a product surface that needs a compact,
  /// structured editor instead of the generic object renderer.
  ///
  /// This stays metadata-only so the schema package remains Flutter-free.
  final String? editor;
  final bool? allowMargin;
  final bool? allowPadding;
  final bool? allowHorizontalAlign;
  final bool? allowVerticalAlign;
}

Object? constructDartDataInputDefault(DartDataInputSchema schema) {
  if (schema.defaultValue != null) {
    final defaultValue = _cloneDataInputValue(schema.defaultValue);
    if (defaultValue is Map &&
        defaultValue.isEmpty &&
        schema.fields.isNotEmpty) {
      for (final field in schema.fields) {
        final value = constructDartDataInputDefault(field);
        if (value != null) defaultValue[field.key ?? field.label] = value;
      }
    }
    return defaultValue;
  }
  switch (schema.kind) {
    case DartDataInputKind.object:
      final values = <String, dynamic>{};
      for (final field in schema.fields) {
        final value = constructDartDataInputDefault(field);
        if (value != null) values[field.key ?? field.label] = value;
      }
      return values;
    case DartDataInputKind.array:
      return <dynamic>[];
    case DartDataInputKind.number:
    case DartDataInputKind.duration:
      return schema.required ? 0 : null;
    case DartDataInputKind.keyboardKey:
      return null;
    case DartDataInputKind.keyCombo:
      return <dynamic>[];
    case DartDataInputKind.lightColor:
      return null;
    case DartDataInputKind.obsTransform:
      return <String, dynamic>{};
    case DartDataInputKind.boolean:
      return schema.required ? false : null;
    case DartDataInputKind.text:
    case DartDataInputKind.multilineText:
    case DartDataInputKind.filePath:
    case DartDataInputKind.resource:
      return schema.required ? '' : null;
    case DartDataInputKind.enumeration:
    case DartDataInputKind.color:
      return null;
  }
}

Object? _cloneDataInputValue(Object? value) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        entry.key.toString(): _cloneDataInputValue(entry.value),
    };
  }
  if (value is List) {
    return value.map(_cloneDataInputValue).toList();
  }
  return value;
}
