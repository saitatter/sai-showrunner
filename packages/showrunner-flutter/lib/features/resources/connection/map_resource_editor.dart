part of '../resource_editor_registry.dart';

class _MapResourceEditor extends StatefulWidget {
  const _MapResourceEditor({
    required this.title,
    required this.resource,
    required this.fields,
    required this.onSave,
    this.secretFields = const <String>{},
  });

  final String title;
  final ResourceData resource;
  final List<String> fields;
  final Future<void> Function(ResourceData resource) onSave;
  final Set<String> secretFields;

  @override
  State<_MapResourceEditor> createState() => _MapResourceEditorState();
}

class _MapResourceEditorState extends State<_MapResourceEditor> {
  late final Map<String, dynamic> _values;

  @override
  void initState() {
    super.initState();
    _values = {
      for (final field in widget.fields) field: widget.resource.config[field],
    };
  }

  @override
  Widget build(BuildContext context) => _ResourceForm(
    title: widget.title,
    fields: [
      for (final field in widget.fields)
        DartDataInput(
          schema: _schemaFor(field),
          value: _values[field],
          onChanged: (value) => setState(() => _values[field] = value),
        ),
    ],
    onSave: () => widget.onSave(
      ResourceData(
        id: widget.resource.id,
        config: {...widget.resource.config, ..._values},
        state: widget.resource.state,
      ),
    ),
  );

  DartDataInputSchema _schemaFor(String field) {
    final kind = switch (field) {
      'port' ||
      'cost' ||
      'numberOfLights' ||
      'ledCount' => DartDataInputKind.number,
      'local' ||
      'rgbAvailable' ||
      'kelvinAvailable' ||
      'dimmingAvailable' ||
      'transitionsAvailable' => DartDataInputKind.boolean,
      'userIds' => DartDataInputKind.array,
      'installPath' => DartDataInputKind.filePath,
      _ => DartDataInputKind.text,
    };
    return DartDataInputSchema(
      label: field,
      kind: kind,
      secret:
          widget.secretFields.contains(field) ||
          field.toLowerCase().contains('password'),
    );
  }
}

String _displayValue(dynamic value) {
  if (value is List) return value.join(', ');
  return value?.toString() ?? '';
}

String _jsonDisplayValue(dynamic value) {
  if (value is Map) return jsonEncode(value);
  return _displayValue(value);
}

dynamic _parseJsonMap(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return <String, dynamic>{};
  try {
    final decoded = jsonDecode(trimmed);
    return decoded is Map<String, dynamic> ? decoded : trimmed;
  } on FormatException {
    return trimmed;
  }
}
