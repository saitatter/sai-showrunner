import 'dart:math' as math;

typedef ObsTransformMap = Map<String, dynamic>;

ObsTransformMap normalizeObsTransform(dynamic value) {
  final source = value is Map
      ? Map<String, dynamic>.from(value)
      : <String, dynamic>{};
  return {
    ...source,
    'position': _group(source['position']),
    'scale': _group(source['scale']),
    'crop': _group(source['crop']),
    'boundingBox': _group(source['boundingBox']),
  };
}

ObsTransformMap obsTransformToWebSocket(dynamic value) {
  final transform = normalizeObsTransform(value);
  final position = _map(transform['position']);
  final scale = _map(transform['scale']);
  final crop = _map(transform['crop']);
  final bounds = _map(transform['boundingBox']);
  final result = <String, dynamic>{};

  _copy(result, 'positionX', position['x']);
  _copy(result, 'positionY', position['y']);
  _copy(result, 'rotation', transform['rotation']);
  _copy(result, 'alignment', transform['alignment']);
  _copy(result, 'scaleX', scale['x']);
  _copy(result, 'scaleY', scale['y']);
  _copy(result, 'cropTop', crop['top']);
  _copy(result, 'cropRight', crop['right']);
  _copy(result, 'cropBottom', crop['bottom']);
  _copy(result, 'cropLeft', crop['left']);
  _copy(result, 'boundsAlignment', bounds['alignment']);
  _copy(result, 'boundsType', bounds['boxType']);
  if (bounds['width'] is num) {
    result['boundsWidth'] = math.max<double>(
      (bounds['width'] as num).toDouble(),
      1,
    );
  }
  if (bounds['height'] is num) {
    result['boundsHeight'] = math.max<double>(
      (bounds['height'] as num).toDouble(),
      1,
    );
  }
  return result;
}

ObsTransformMap _group(dynamic value) => value is Map
    ? Map<String, dynamic>.from(value)
    : <String, dynamic>{};

Map<String, dynamic> _map(dynamic value) => value is Map
    ? Map<String, dynamic>.from(value)
    : const <String, dynamic>{};

void _copy(Map<String, dynamic> target, String key, dynamic value) {
  if (value != null) target[key] = value;
}