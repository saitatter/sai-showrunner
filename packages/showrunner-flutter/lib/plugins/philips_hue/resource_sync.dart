import 'dart:io';
import 'dart:math' as math;

import '../../persistence/resource_repository.dart';
import '../../schema/automation.dart';
import '../../schema/resource.dart';
import 'manifest.dart';

final class PhilipsHueResourceSynchronizer {
  const PhilipsHueResourceSynchronizer({
    required this.lightDirectory,
    required this.plugDirectory,
  });

  final Directory lightDirectory;
  final Directory plugDirectory;

  Future<void> sync(HueTransport transport) async {
    final lightsResponse = await transport.request(
      'GET',
      '/resource/light',
      const {},
      null,
    );
    final lightRepository = ResourceRepository(lightDirectory);
    final plugRepository = ResourceRepository(plugDirectory);
    final lights = _maps(lightsResponse['data']);
    for (final light in lights) {
      final id = _requiredId(light);
      if (id == null) continue;
      final hasLightControls =
          light.containsKey('color') ||
          light.containsKey('color_temperature') ||
          light.containsKey('dimming');
      final resource = ResourceData(
        id: 'philips-hue.$id',
        config: hasLightControls
            ? _lightConfig(light, id)
            : _plugConfig(light, id),
        state: _state(light),
      );
      if (hasLightControls) {
        await lightRepository.save(resource);
      } else {
        await plugRepository.save(resource);
      }
    }

    final roomsResponse = await transport.request(
      'GET',
      '/resource/room',
      const {},
      null,
    );
    final rooms = _maps(roomsResponse['data']);
    for (final room in rooms) {
      final groupId = _groupId(room);
      if (groupId == null) continue;
      JsonMap groupState = const {};
      try {
        final groupResponse = await transport.request(
          'GET',
          '/resource/grouped_light/$groupId',
          const {},
          null,
        );
        groupState = _state(_firstMap(groupResponse['data']) ?? const {});
      } catch (_) {
        // Keep the discovered group available when only its state request
        // fails. The next settings/resource refresh can populate the state.
      }
      final childIds = _strings(room['children']);
      final lightIds = <String>[];
      for (final childId in childIds) {
        try {
          final deviceResponse = await transport.request(
            'GET',
            '/resource/device/$childId',
            const {},
            null,
          );
          for (final service in _maps(
            _firstMap(deviceResponse['data'])?['services'],
          )) {
            if (service['rtype'] == 'light' && service['rid'] != null) {
              lightIds.add(service['rid'].toString());
            }
          }
        } catch (_) {
          // A missing device should not prevent the rest of the room from
          // remaining available as a grouped-light resource.
        }
      }
      await lightRepository.save(
        ResourceData(
          id: 'philips-hue.$groupId',
          config: {
            'name': _mapValue(room['metadata'])?['name']?.toString() ?? groupId,
            'provider': 'philips-hue',
            'providerId': groupId,
            'hueType': 'group',
            'lightIds': lightIds,
            'roomId': room['id']?.toString() ?? '',
            'rgb': {'available': true},
            'kelvin': {'available': true},
            'dimming': {'available': true},
            'transitions': {'available': true},
          },
          state: groupState,
        ),
      );
    }
  }
}

JsonMap _lightConfig(JsonMap light, String id) {
  final colorTemperature = _mapValue(light['color_temperature']);
  final mirekSchema = _mapValue(colorTemperature?['mirek_schema']);
  return {
    'name': _mapValue(light['metadata'])?['name']?.toString() ?? id,
    'provider': 'philips-hue',
    'providerId': id,
    'rgb': {'available': light.containsKey('color')},
    'kelvin': {
      'available': colorTemperature != null,
      if (mirekSchema?['mirek_minimum'] is num)
        'min': 1000000 / (mirekSchema!['mirek_minimum'] as num),
      if (mirekSchema?['mirek_maximum'] is num)
        'max': 1000000 / (mirekSchema!['mirek_maximum'] as num),
    },
    'dimming': {'available': light.containsKey('dimming')},
    'transitions': {'available': true},
  };
}

JsonMap _plugConfig(JsonMap light, String id) => {
  'name': _mapValue(light['metadata'])?['name']?.toString() ?? id,
  'provider': 'philips-hue',
  'providerId': id,
};

JsonMap _state(JsonMap light) {
  final on = _mapValue(light['on']);
  final state = <String, dynamic>{'on': on?['on'] == true};
  final brightness = _number(_mapValue(light['dimming'])?['brightness'], 100);
  final colorTemperature = _mapValue(light['color_temperature']);
  final mirek = colorTemperature?['mirek'];
  if (mirek is num && mirek > 0) {
    state['color'] =
        'kb(${(1000000 / mirek).round()}, '
        '${brightness.round()})';
    return state;
  }
  final color = _mapValue(light['color']);
  final xy = _mapValue(color?['xy']);
  final x = _number(xy?['x'], double.nan);
  final y = _number(xy?['y'], double.nan);
  if (x.isFinite && y.isFinite && y > 0) {
    final hsb = _xyToHsb(x, y);
    state['color'] =
        'hsb(${_format(hsb.$1)}, ${_format(hsb.$2)}, '
        '${brightness.round()})';
  }
  return state;
}

String? _requiredId(JsonMap value) {
  final id = value['id']?.toString().trim();
  return id == null || id.isEmpty ? null : id;
}

String? _groupId(JsonMap room) {
  final services = _maps(room['services']);
  for (final service in services) {
    if (service['rtype'] != 'grouped_light') continue;
    final id = service['rid']?.toString().trim();
    if (id != null && id.isNotEmpty) return id;
  }
  return null;
}

List<JsonMap> _maps(Object? value) => value is List
    ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
    : <JsonMap>[];

List<String> _strings(Object? value) => value is List
    ? value
          .whereType<Map>()
          .map((item) => item['rid']?.toString().trim() ?? '')
          .where((value) => value.isNotEmpty)
          .toList()
    : <String>[];

JsonMap? _mapValue(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;

JsonMap? _firstMap(Object? value) {
  final maps = _maps(value);
  return maps.isEmpty ? null : maps.first;
}

double _number(Object? value, double fallback) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? fallback;

(double, double) _xyToHsb(double x, double y) {
  final z = 1 - x - y;
  final red = 3.2406 * (x / y) - 1.5372 - 0.4986 * (z / y);
  final green = -0.9689 * (x / y) + 1.8758 + 0.0415 * (z / y);
  final blue = 0.0557 * (x / y) - 0.2040 + 1.0570 * (z / y);
  final maximum = math.max(red, math.max(green, blue));
  final minimum = math.min(red, math.min(green, blue));
  final range = maximum - minimum;
  if (maximum <= 0 || range <= 0) return (0, 0);
  final hue = switch (maximum) {
    _ when maximum == red => 60 * ((green - blue) / range % 6),
    _ when maximum == green => 60 * ((blue - red) / range + 2),
    _ => 60 * ((red - green) / range + 4),
  };
  return ((hue + 360) % 360, (range / maximum * 100).clamp(0, 100));
}

String _format(double value) =>
    value == value.roundToDouble() ? value.round().toString() : '$value';
