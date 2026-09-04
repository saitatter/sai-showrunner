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

  factory ResourceData.fromJson(JsonMap json) => ResourceData(
    id: json['id'] as String? ?? '',
    config: (json['config'] as JsonMap?) ?? const <String, dynamic>{},
    state: (json['state'] as JsonMap?) ?? const <String, dynamic>{},
  );

  JsonMap toJson() => <String, dynamic>{
    'id': id,
    'config': config,
    'state': state,
  };
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
    final widgetsList =
        (config['widgets'] as List<dynamic>?)?.whereType<JsonMap>().toList() ??
        const [];
    return OverlayResource(
      id: resource.id,
      name: resource.name,
      width: (config['width'] as num?)?.toInt() ?? 1920,
      height: (config['height'] as num?)?.toInt() ?? 1080,
      widgets: widgetsList,
    );
  }

  ResourceData toResource() => ResourceData(
    id: id,
    config: <String, dynamic>{
      'name': name,
      'width': width,
      'height': height,
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
  final dynamic defaultValue;
  final dynamic currentValue;
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
