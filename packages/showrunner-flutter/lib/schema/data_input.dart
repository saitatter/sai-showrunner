/// Flutter-free data input contracts used by plugin manifests and schemas.
library;

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
  });

  final String label;
  final DartDataInputKind kind;
  final String? key;
  final List<String> options;
  final bool required;
  final bool secret;
  final bool multiline;
  final dynamic defaultValue;
  final String? resourceType;
  final List<DartDataInputSchema> fields;
  final DartDataInputKind itemKind;
  final DartDataInputSchema? itemSchema;
}

dynamic constructDartDataInputDefault(DartDataInputSchema schema) {
  if (schema.defaultValue != null) {
    return _cloneDataInputValue(schema.defaultValue);
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

dynamic _cloneDataInputValue(dynamic value) {
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
