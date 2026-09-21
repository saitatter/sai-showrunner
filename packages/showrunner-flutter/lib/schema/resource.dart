import 'automation.dart';

class ResourceData {
  const ResourceData({
    required this.id,
    required this.config,
    this.state = const <String, dynamic>{},
  });

  final String id;
  final JsonMap config;
  final JsonMap state;

  String get name => (config['name'] as String?) ?? id;

  factory ResourceData.fromJson(JsonMap json) {
    final id = json['id'];
    if (id is! String || id.trim().isEmpty) {
      throw const FormatException('Resource JSON must contain a non-empty id.');
    }
    return ResourceData(
      id: id,
      config: _requiredMap(json, 'config'),
      state: _optionalMap(json, 'state'),
    );
  }

  JsonMap toJson() => <String, dynamic>{
    'id': id,
    'config': config,
    'state': state,
  };
}

JsonMap _requiredMap(JsonMap json, String field) {
  final value = json[field];
  if (value is! Map) {
    throw FormatException('Resource JSON field "$field" must be an object.');
  }
  return Map<String, dynamic>.from(value);
}

JsonMap _optionalMap(JsonMap json, String field) {
  final value = json[field];
  if (value == null) return const <String, dynamic>{};
  if (value is! Map) {
    throw FormatException('Resource JSON field "$field" must be an object.');
  }
  return Map<String, dynamic>.from(value);
}

class OverlayResource {
  const OverlayResource({
    required this.id,
    required this.name,
    this.width = 1920,
    this.height = 1080,
    this.widgets = const <JsonMap>[],
  });

  final String id;
  final String name;
  final int width;
  final int height;
  final List<JsonMap> widgets;

  factory OverlayResource.fromResource(ResourceData resource) {
    final config = resource.config;
    final rawSize = config['size'];
    if (rawSize is! Map) {
      throw const FormatException('Overlay config must contain a size object.');
    }
    final size = Map<String, dynamic>.from(rawSize);
    final rawWidgets = config['widgets'];
    if (rawWidgets is! List) {
      throw const FormatException(
        'Overlay config must contain a widgets list.',
      );
    }
    final widgetsList = rawWidgets
        .whereType<Map>()
        .map((widget) => Map<String, dynamic>.from(widget))
        .toList();
    return OverlayResource(
      id: resource.id,
      name: resource.name,
      width: (size['width'] as num?)?.toInt() ?? 1920,
      height: (size['height'] as num?)?.toInt() ?? 1080,
      widgets: widgetsList,
    );
  }

  ResourceData toResource() => ResourceData(
    id: id,
    config: <String, dynamic>{
      'name': name,
      'size': {'width': width, 'height': height},
      'widgets': widgets,
    },
  );
}

class VariableResource {
  const VariableResource({
    required this.id,
    required this.name,
    required this.type,
    this.defaultValue,
    this.currentValue,
    this.persistent = true,
  });

  final String id;
  final String name;
  final String type;
  final Object? defaultValue;
  final Object? currentValue;
  final bool persistent;

  factory VariableResource.fromResource(ResourceData resource) {
    final config = resource.config;
    return VariableResource(
      id: resource.id,
      name: resource.name,
      type: (config['type'] as String?) ?? 'string',
      defaultValue: config['defaultValue'],
      currentValue: resource.state['value'] ?? config['defaultValue'],
      persistent: (config['persistent'] as bool?) ?? true,
    );
  }

  ResourceData toResource() => ResourceData(
    id: id,
    config: <String, dynamic>{
      'name': name,
      'type': type,
      'defaultValue': defaultValue,
      'persistent': persistent,
    },
    state: <String, dynamic>{'value': currentValue},
  );
}
