import 'dart:convert';
import '../../../schema/automation.dart';
import '../../../schema/resource.dart';
import '../../../schema/data_input.dart';

/// The editable document owns its JSON tree; editing never mutates the loaded resource.
final class OverlayDocument {
  OverlayDocument(ResourceData resource)
    : source = ResourceData.fromJson(
        Map<String, dynamic>.from(
          jsonDecode(jsonEncode(resource.toJson())) as Map,
        ),
      );
  final ResourceData source;
  List<JsonMap> get initialWidgets {
    final overlay = OverlayResource.fromResource(source);
    return overlay.widgets.map((widget) {
      final size = widget['size'];
      if (size is! Map) return widget;
      return <String, dynamic>{
        ...widget,
        'size': {
          ...Map<String, dynamic>.from(size),
          if (size['width'] == 'canvas') 'width': overlay.width,
          if (size['height'] == 'canvas') 'height': overlay.height,
        },
      };
    }).toList();
  }

  ResourceData snapshot({
    required String name,
    required int width,
    required int height,
    required List<JsonMap> widgets,
    JsonMap? preview,
  }) {
    final config =
        <String, dynamic>{
            ...source.config,
            'name': name,
            'size': {'width': width, 'height': height},
            'widgets': widgets,
          }
          ..remove('width')
          ..remove('height');
    if (preview == null) {
      config.remove('preview');
    } else {
      config['preview'] = preview;
    }
    return ResourceData.fromJson(
      Map<String, dynamic>.from(
        jsonDecode(
              jsonEncode(
                ResourceData(
                  id: source.id,
                  config: config,
                  state: source.state,
                ).toJson(),
              ),
            )
            as Map,
      ),
    );
  }
}

JsonMap mergeOverlayWidgetDefaults(DartDataInputSchema schema, Object? value) {
  if (schema.kind != DartDataInputKind.object) {
    return value is Map
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{};
  }

  final current = value is Map
      ? Map<String, dynamic>.from(value)
      : <String, dynamic>{};
  final defaults = constructDartDataInputDefault(schema);
  if (defaults is Map) {
    for (final entry in defaults.entries) {
      current.putIfAbsent(entry.key.toString(), () => entry.value);
    }
  }
  for (final field in schema.fields) {
    final key = field.key ?? field.label;
    if (!current.containsKey(key)) continue;
    final fieldValue = current[key];
    if (field.kind == DartDataInputKind.object) {
      current[key] = mergeOverlayWidgetDefaults(field, fieldValue);
    }
  }
  return current;
}
