import 'dart:convert';
import '../../schema/json.dart';
import '../../schema/resource.dart';
import 'overlay_media_resources.dart';
import 'overlay_widget_catalog.generated.dart';
import 'overlay_projection_policy.dart';

/// Render DTO projection, independent of persisted shader/editor documents.
Future<JsonMap> projectOverlayConfig(
  ResourceData resource,
  OverlayMediaResources media,
) async {
  final config = resource.config;
  final rawSize = config['size'];
  if (rawSize is! Map || config['widgets'] is! List) {
    throw const FormatException(
      'Overlay config must contain size and widgets fields.',
    );
  }
  final size = Map<String, dynamic>.from(rawSize);
  final width = _dimension(size['width'], 1920);
  final height = _dimension(size['height'], 1080);
  if (width <= 0 ||
      height <= 0 ||
      width > 8192 ||
      height > 8192 ||
      width * height > 33554432 ||
      (config['widgets'] as List).length > 256) {
    throw const FormatException('Overlay resource limits exceeded.');
  }
  if ((config['widgets'] as List)
          .whereType<Map>()
          .where(
            (widget) =>
                widget['plugin'] == 'overlays' &&
                widget['widget'] == 'shaderLayer',
          )
          .length >
      8) {
    throw const FormatException('Overlay shader layer limit exceeded.');
  }
  final values = _ConfigValueProjector(media, resource.id);
  final widgets = <JsonMap>[];
  final ids = <String>{};
  for (final raw in config['widgets'] as List) {
    if (raw is! Map) throw const FormatException('Invalid overlay widget.');
    final widget = await _remoteWidget(Map<String, dynamic>.from(raw), values);
    if (!ids.add(widget['id'] as String)) {
      throw const FormatException('Duplicate overlay widget ID.');
    }
    widgets.add(widget);
  }
  final result = <String, dynamic>{
    'name': resource.name,
    'schemaVersion': 1,
    'size': {'width': width, 'height': height},
    'widgets': widgets,
  };
  if (utf8.encode(jsonEncode(result)).length > 1024 * 1024) {
    throw const FormatException('Overlay config exceeds its transport limit.');
  }
  return result;
}

Future<JsonMap> _remoteWidget(
  JsonMap widget,
  _ConfigValueProjector values,
) async {
  final size = widget['size'] is Map
      ? Map<String, dynamic>.from(widget['size'] as Map)
      : const <String, dynamic>{};
  final position = widget['position'] is Map
      ? Map<String, dynamic>.from(widget['position'] as Map)
      : const <String, dynamic>{};
  final id = widget['id'];
  if (id is! String || id.isEmpty || id.length > 128) {
    throw const FormatException('Invalid overlay widget ID.');
  }
  final definition = generatedOverlayWidgets
      .where(
        (entry) =>
            entry.pluginId == widget['plugin'] && entry.id == widget['widget'],
      )
      .firstOrNull;
  final publicConfig = <String, dynamic>{};
  final config = widget['config'];
  if (definition != null && config is Map) {
    for (final entry in definition.config.entries) {
      final metadata = entry.value;
      if (!config.containsKey(entry.key) ||
          (metadata is Map &&
              (metadata['secret'] == true || metadata['browser'] == false)) ||
          isPrivateOverlayField(entry.key)) {
        continue;
      }
      publicConfig[entry.key] = await values.project(config[entry.key], 0);
    }
  }
  return {
    'id': id,
    'plugin': widget['plugin']?.toString() ?? 'overlays',
    'widget': widget['widget']?.toString() ?? '',
    'name': widget['name']?.toString() ?? widget['widget']?.toString() ?? '',
    'size': {
      'width': _dimension(size['width'], 100),
      'height': _dimension(size['height'], 100),
    },
    'position': {
      'x': _coordinate(position['x']),
      'y': _coordinate(position['y']),
    },
    'config': publicConfig,
    'locked': widget['locked'] == true,
    'visible': widget['visible'] != false,
  };
}

int _dimension(Object? value, int fallback) {
  if (value == null) return fallback;
  if (value is! num || !value.isFinite || value < 1 || value > 8192) {
    throw const FormatException('Invalid overlay dimensions.');
  }
  return value.toInt();
}

double _coordinate(Object? value) {
  if (value == null) return 0;
  if (value is! num || !value.isFinite || value.abs() > 1000000) {
    throw const FormatException('Invalid overlay coordinates.');
  }
  return value.toDouble();
}

final class _ConfigValueProjector {
  _ConfigValueProjector(this.media, this.overlayId);
  final OverlayMediaResources media;
  final String overlayId;
  int remaining = 16384;
  Future<Object?> project(Object? value, int depth) async {
    if (remaining-- <= 0 || depth > 16) {
      throw const FormatException('Overlay config nesting limit exceeded.');
    }
    if (value == null || value is bool) return value;
    if (value is num) return value.isFinite ? value : null;
    if (value is String) {
      if (value.length > 131072) {
        throw const FormatException('Overlay string limit exceeded.');
      }
      if (RegExp(
        r'^(?:[a-zA-Z]:[\\/]|\\\\|file:|/(?:Users|home|root|tmp|var|etc|mnt)/)',
        caseSensitive: false,
      ).hasMatch(value)) {
        if (value.startsWith('file:')) return null;
        return media.browserUrl(value, overlayId);
      }
      return value;
    }
    if (value is List) {
      if (value.length > 1024) {
        throw const FormatException('Overlay list limit exceeded.');
      }
      return [for (final item in value) await project(item, depth + 1)];
    }
    if (value is Map) {
      if (value.length > 1024) {
        throw const FormatException('Overlay map limit exceeded.');
      }
      return {
        for (final entry in value.entries)
          if (entry.key is String &&
              !isPrivateOverlayField(entry.key as String))
            entry.key as String: await project(entry.value, depth + 1),
      };
    }
    throw const FormatException('Unsupported overlay render value.');
  }
}
