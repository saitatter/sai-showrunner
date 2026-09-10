import '../../schema/data_input.dart';

class GeneratedOverlayWidget {
  const GeneratedOverlayWidget({
    required this.pluginId,
    required this.id,
    required this.name,
    this.description,
    this.icon,
    required this.defaultSize,
    this.config = const <String, dynamic>{},
    this.capabilities = const <String, dynamic>{},
  });

  final String pluginId;
  final String id;
  final String name;
  final String? description;
  final String? icon;
  final Map<String, dynamic> defaultSize;
  final Map<String, dynamic> config;
  final Map<String, dynamic> capabilities;

  String get key => '$pluginId.$id';

  DartDataInputSchema get configSchema =>
      overlayConfigSchema(label: 'Configuration', config: config);

  Map<String, dynamic> defaultConfig() {
    final value = constructDartDataInputDefault(configSchema);
    return value is Map
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{};
  }

  Map<String, dynamic> createWidget({String? widgetId}) => {
    'id': widgetId ?? 'widget-${DateTime.now().microsecondsSinceEpoch}',
    'plugin': pluginId,
    'widget': id,
    'name': name,
    'size': _cloneMap(defaultSize),
    'position': {'x': 0, 'y': 0},
    'config': defaultConfig(),
    'visible': true,
    'locked': false,
  };
}

/// Converts the language-neutral manifest schema into the Flutter-free data
/// input contract used by the existing generic form renderer.
DartDataInputSchema overlayConfigSchema({
  required String label,
  required Map<String, dynamic> config,
}) => DartDataInputSchema(
  label: label,
  kind: DartDataInputKind.object,
  fields: [
    for (final entry in config.entries) _schemaFor(entry.key, entry.value),
  ],
);

DartDataInputSchema _schemaFor(String key, Object? raw) {
  final metadata = raw is Map
      ? Map<String, dynamic>.from(raw)
      : <String, dynamic>{'type': raw?.toString() ?? 'string'};
  final type = '${metadata['type'] ?? 'string'}'.toLowerCase();
  final defaultValue = metadata.containsKey('default')
      ? _cloneValue(metadata['default'])
      : null;
  final fields = metadata['fields'] is Map
      ? [
          for (final entry in (metadata['fields'] as Map).entries)
            _schemaFor(entry.key.toString(), entry.value),
        ]
      : metadata['fields'] is List
      ? [
          for (final item in metadata['fields'] as List)
            if (item is Map && item['key'] != null)
              _schemaFor(item['key'].toString(), item),
        ]
      : const <DartDataInputSchema>[];
  final kind = switch (type) {
    'multilinetext' || 'multiline' => DartDataInputKind.multilineText,
    'number' || 'integer' || 'float' => DartDataInputKind.number,
    'boolean' || 'bool' => DartDataInputKind.boolean,
    'color' => DartDataInputKind.color,
    'duration' => DartDataInputKind.duration,
    'array' || 'list' => DartDataInputKind.array,
    'object' || 'map' || 'json' || 'range' => DartDataInputKind.object,
    'filepath' || 'file' => DartDataInputKind.filePath,
    'resource' => DartDataInputKind.resource,
    'enum' || 'enumeration' => DartDataInputKind.enumeration,
    'viewervariable' => DartDataInputKind.text,
    _ => DartDataInputKind.text,
  };
  final rangeFields = type == 'range' && fields.isEmpty
      ? [
          _schemaFor('min', {
            'type': 'number',
            if (defaultValue is Map && defaultValue['min'] != null)
              'default': defaultValue['min'],
          }),
          _schemaFor('max', {
            'type': 'number',
            if (defaultValue is Map && defaultValue['max'] != null)
              'default': defaultValue['max'],
          }),
        ]
      : fields;
  final itemMetadata = metadata['itemSchema'] ?? metadata['item'];
  final itemSchema = itemMetadata is Map
      ? _schemaFor('Item', itemMetadata)
      : null;
  return DartDataInputSchema(
    key: key,
    label: '${metadata['name'] ?? _humanize(key)}',
    kind: kind,
    options: metadata['enum'] is List
        ? (metadata['enum'] as List).map((value) => '$value').toList()
        : metadata['options'] is List
        ? (metadata['options'] as List).map((value) => '$value').toList()
        : const <String>[],
    required: metadata['required'] == true,
    secret: metadata['secret'] == true,
    multiline: metadata['multiLine'] == true || metadata['multiline'] == true,
    defaultValue: defaultValue,
    resourceType: metadata['resourceType']?.toString(),
    fields: rangeFields,
    itemKind: _itemKind(metadata['itemType']),
    itemSchema: itemSchema,
  );
}

DartDataInputKind _itemKind(Object? value) {
  final type = '$value'.toLowerCase();
  return switch (type) {
    'number' || 'integer' || 'float' => DartDataInputKind.number,
    'boolean' || 'bool' => DartDataInputKind.boolean,
    'object' || 'map' || 'json' => DartDataInputKind.object,
    _ => DartDataInputKind.text,
  };
}

String _humanize(String value) => value
    .replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (match) => '${match.group(1)} ${match.group(2)}',
    )
    .replaceAll(RegExp(r'[_-]+'), ' ')
    .split(' ')
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');

dynamic _cloneValue(Object? value) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        entry.key.toString(): _cloneValue(entry.value),
    };
  }
  if (value is List) return value.map(_cloneValue).toList();
  return value;
}

Map<String, dynamic> _cloneMap(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(_cloneValue(value) as Map);
