import 'automation.dart';

String normalizeViewerVariableType(String type) {
  switch (type.trim().toLowerCase()) {
    case 'string':
      return 'string';
    case 'number':
      return 'number';
    case 'boolean':
      return 'boolean';
    default:
      throw ArgumentError.value(
        type,
        'type',
        'Supported viewer variable types are string, number, and boolean.',
      );
  }
}

dynamic normalizeViewerVariableValue(String type, dynamic value) {
  if (value == null) return null;

  switch (normalizeViewerVariableType(type)) {
    case 'string':
      if (value is String) return value;
    case 'number':
      if (value is num && value.isFinite) return value;
    case 'boolean':
      if (value is bool) return value;
  }

  throw ArgumentError.value(value, 'value', 'Value does not match type $type.');
}

final class ViewerVariableDefinition {
  const ViewerVariableDefinition({
    required this.name,
    required this.type,
    this.defaultValue,
    this.required = true,
  });

  final String name;
  final String type;
  final dynamic defaultValue;
  final bool required;

  String get normalizedType => normalizeViewerVariableType(type);

  dynamic get constructedDefault {
    if (defaultValue != null) {
      return normalizeViewerVariableValue(normalizedType, defaultValue);
    }
    if (!required) return null;
    switch (normalizedType) {
      case 'string':
        return '';
      case 'number':
        return 0;
      case 'boolean':
        return false;
    }
    throw StateError('Unsupported viewer variable type: $type');
  }

  factory ViewerVariableDefinition.fromJson(JsonMap json) {
    final name = json['name'] as String? ?? '';
    if (name.trim().isEmpty) {
      throw const FormatException('Viewer variable name cannot be empty.');
    }
    final type = json['type'] as String? ?? '';
    normalizeViewerVariableType(type);
    final defaultValue = json['defaultValue'];
    if (defaultValue != null) {
      normalizeViewerVariableValue(type, defaultValue);
    }
    return ViewerVariableDefinition(
      name: name,
      type: type,
      defaultValue: defaultValue,
      required: json['required'] as bool? ?? true,
    );
  }

  JsonMap toJson() => {
    'name': name,
    'type': type,
    if (defaultValue != null) 'defaultValue': defaultValue,
    'required': required,
  };
}

final class ViewerIdentity {
  const ViewerIdentity({required this.id, required this.displayName});

  final String id;
  final String displayName;

  factory ViewerIdentity.fromConfig(dynamic value) {
    if (value is String && value.trim().isNotEmpty) {
      return ViewerIdentity(id: value, displayName: value);
    }
    if (value is Map) {
      final id = value['id']?.toString().trim() ?? '';
      if (id.isEmpty) {
        throw const FormatException('Viewer configuration requires an id.');
      }
      final displayName =
          value['displayName']?.toString() ?? value['name']?.toString() ?? id;
      return ViewerIdentity(id: id, displayName: displayName);
    }
    throw ArgumentError.value(
      value,
      'viewer',
      'Expected a viewer id or an object with an id and displayName.',
    );
  }

  JsonMap toJson() => {'id': id, 'displayName': displayName};
}

final class ViewerDataRow {
  const ViewerDataRow({
    required this.provider,
    required this.viewer,
    required this.values,
    this.persisted = true,
  });

  final String provider;
  final ViewerIdentity viewer;
  final JsonMap values;
  final bool persisted;

  JsonMap toJson() => {
    'provider': provider,
    'id': viewer.id,
    'displayName': viewer.displayName,
    'values': values,
  };

  factory ViewerDataRow.fromJson(JsonMap json) {
    final provider = json['provider'] as String? ?? '';
    final id = json['id'] as String? ?? '';
    if (provider.isEmpty || id.isEmpty) {
      throw const FormatException('Viewer data row requires provider and id.');
    }
    final rawValues = json['values'];
    final values = rawValues is Map
        ? <String, dynamic>{
            for (final entry in rawValues.entries)
              entry.key.toString(): entry.value,
          }
        : <String, dynamic>{};
    return ViewerDataRow(
      provider: provider,
      viewer: ViewerIdentity(
        id: id,
        displayName: json['displayName'] as String? ?? id,
      ),
      values: values,
    );
  }
}
