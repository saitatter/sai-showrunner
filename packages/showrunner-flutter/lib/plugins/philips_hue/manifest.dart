import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../../components/data_inputs/data_input.dart';
import '../../runtime/expression.dart';
import '../iot/light_color.dart';
import '../registry/plugin_registry.dart';

typedef HueRequest =
    Future<RuntimeMap> Function(
      String method,
      String path,
      RuntimeMap query,
      dynamic body,
    );

final class HueTransport {
  const HueTransport(this.request);

  final HueRequest request;
}

typedef HueTransportResolver = HueTransport Function(RuntimeMap config);

final class HueHttpTransport {
  const HueHttpTransport({required this.host, required this.applicationKey});

  final String host;
  final String applicationKey;

  Future<RuntimeMap> request(
    String method,
    String path,
    RuntimeMap query,
    dynamic body,
  ) async {
    final client = HttpClient()
      ..badCertificateCallback = (certificate, host, port) => true;
    try {
      final uri = Uri.parse('https://$host/clip/v2$path').replace(
        queryParameters: {
          ...query.map((key, value) => MapEntry(key, '$value')),
        },
      );
      final request = await client.openUrl(method, uri);
      request.headers.contentType = ContentType.json;
      request.headers.set('hue-application-key', applicationKey);
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close();
      final text = await utf8.decoder.bind(response).join();
      dynamic decoded;
      if (text.isNotEmpty) decoded = jsonDecode(text);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Philips Hue request failed (${response.statusCode}): $text',
        );
      }
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } finally {
      client.close(force: true);
    }
  }
}

const _deviceSchema = DartDataInputSchema(
  label: 'Hue light',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Resource ID',
      key: 'lightId',
      kind: DartDataInputKind.text,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Bridge IP / Host',
      key: 'host',
      kind: DartDataInputKind.text,
    ),
    DartDataInputSchema(
      label: 'Bridge application key',
      key: 'hubKey',
      kind: DartDataInputKind.text,
      secret: true,
    ),
    DartDataInputSchema(
      label: 'Resource type',
      key: 'resourceType',
      kind: DartDataInputKind.enumeration,
      options: ['light', 'grouped_light'],
      defaultValue: 'light',
    ),
    DartDataInputSchema(
      label: 'Power',
      key: 'state',
      kind: DartDataInputKind.enumeration,
      options: ['on', 'off', 'toggle'],
      defaultValue: 'on',
    ),
    DartDataInputSchema(
      label: 'Color',
      key: 'color',
      kind: DartDataInputKind.lightColor,
    ),
    DartDataInputSchema(
      label: 'Transition (seconds)',
      key: 'transition',
      kind: DartDataInputKind.number,
      defaultValue: 0.5,
    ),
  ],
);

const _sceneSchema = DartDataInputSchema(
  label: 'Hue scene',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Scene ID',
      key: 'sceneId',
      kind: DartDataInputKind.text,
    ),
    DartDataInputSchema(
      label: 'Scene (legacy config key)',
      key: 'scene',
      kind: DartDataInputKind.text,
    ),
    DartDataInputSchema(
      label: 'Bridge IP / Host',
      key: 'host',
      kind: DartDataInputKind.text,
    ),
    DartDataInputSchema(
      label: 'Bridge application key',
      key: 'hubKey',
      kind: DartDataInputKind.text,
      secret: true,
    ),
  ],
);

DartPluginManifest createPhilipsHuePlugin(
  HueTransport transport, {
  HueTransportResolver? transportResolver,
}) => DartPluginManifest(
  id: 'philips-hue',
  name: 'Philips Hue',
  settings: const [
    DartSettingDefinition(id: 'hubIp', displayName: 'Hue Hub IP'),
    DartSettingDefinition(
      id: 'hubKey',
      displayName: 'Hue Application Key',
      secret: true,
    ),
  ],
  actions: [
    DartActionDefinition(
      pluginId: 'philips-hue',
      actionId: 'listLights',
      displayName: 'List Lights',
      invoke: (config, context) =>
          transport.request('GET', '/resource/light', const {}, null),
    ),
    DartActionDefinition(
      pluginId: 'philips-hue',
      actionId: 'listGroups',
      displayName: 'List Light Groups',
      invoke: (config, context) =>
          transport.request('GET', '/resource/grouped_light', const {}, null),
    ),
    DartActionDefinition(
      pluginId: 'philips-hue',
      actionId: 'listScenes',
      displayName: 'List Scenes',
      invoke: (config, context) =>
          transport.request('GET', '/resource/scene', const {}, null),
    ),
    DartActionDefinition(
      pluginId: 'philips-hue',
      actionId: 'setLightState',
      displayName: 'Set Light State',
      configSchema: _deviceSchema,
      invoke: (config, context) => _setLightState(
        transportResolver?.call(config) ?? transport,
        config,
        context,
      ),
    ),
    DartActionDefinition(
      pluginId: 'philips-hue',
      actionId: 'recallScene',
      displayName: 'Recall Hue Scene',
      configSchema: _sceneSchema,
      invoke: (config, context) =>
          _recallScene(transportResolver?.call(config) ?? transport, config),
    ),
    DartActionDefinition(
      pluginId: 'philips-hue',
      actionId: 'scene',
      displayName: 'Set HUE Scene',
      configSchema: _sceneSchema,
      invoke: (config, context) =>
          _recallScene(transportResolver?.call(config) ?? transport, config),
    ),
  ],
);

Future<Object?> _recallScene(HueTransport transport, RuntimeMap config) =>
    transport.request(
      'PUT',
      '/resource/scene/${_requiredScene(config)}',
      const {},
      {
        'recall': {'action': 'active'},
      },
    );

Future<Object?> _setLightState(
  HueTransport transport,
  RuntimeMap config,
  EvaluationContext context,
) async {
  final resourceType = config['resourceType']?.toString() ?? 'light';
  final lightId = _required(config, 'lightId');
  var power = config['state'] ?? 'on';
  if (power == 'toggle') {
    final current = await transport.request(
      'GET',
      '/resource/$resourceType/$lightId',
      const {},
      null,
    );
    power = !_isOn(current);
  }
  final body = <String, dynamic>{
    'on': {'on': power == true || power == 'on'},
    'dynamics': {
      'duration': ((_number(config['transition'], 0.5)).clamp(0, 600) * 1000)
          .round(),
    },
  };
  final parsedColor = parseLightColor(config['color']?.toString());
  if (parsedColor != null) {
    body['dimming'] = {'brightness': parsedColor.brightness.clamp(0, 100)};
    if (parsedColor.isKelvin) {
      body['color_temperature'] = {
        'mirek': (1000000 / parsedColor.kelvin!).round(),
      };
    } else {
      body['color'] = {'xy': _xy(parsedColor)};
    }
  }
  return transport.request(
    'PUT',
    '/resource/$resourceType/$lightId',
    const {},
    body,
  );
}

String _required(RuntimeMap config, String key) {
  final value = config[key]?.toString().trim() ?? '';
  if (value.isEmpty) throw ArgumentError('$key is required.');
  return value;
}

String _requiredScene(RuntimeMap config) {
  final value = config['sceneId'] ?? config['scene'];
  final scene = value?.toString().trim() ?? '';
  if (scene.isEmpty) throw ArgumentError('scene is required.');
  return scene;
}

double _number(Object? value, double fallback) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? fallback;

bool _isOn(RuntimeMap response) {
  final data = response['data'];
  if (data is List && data.isNotEmpty && data.first is Map) {
    final on = (data.first as Map)['on'];
    if (on is Map && on['on'] is bool) return on['on'] as bool;
  }
  return false;
}

Map<String, double> _xy(LightColorValue value) {
  final hue = (value.hue! % 360 + 360) % 360;
  final saturation = value.saturation!.clamp(0, 100) / 100;
  final brightness = value.brightness.clamp(0, 100) / 100;
  final chroma = brightness * saturation;
  final segment = hue / 60;
  final x = chroma * (1 - ((segment % 2) - 1).abs());
  final (red, green, blue) = switch (segment.floor()) {
    0 => (chroma, x, 0.0),
    1 => (x, chroma, 0.0),
    2 => (0.0, chroma, x),
    3 => (0.0, x, chroma),
    4 => (x, 0.0, chroma),
    _ => (chroma, 0.0, x),
  };
  final match = brightness - chroma;
  final r = _linear(red + match);
  final g = _linear(green + match);
  final b = _linear(blue + match);
  final xValue = r * 0.664511 + g * 0.154324 + b * 0.162028;
  final yValue = r * 0.283881 + g * 0.668433 + b * 0.047685;
  final zValue = r * 0.000088 + g * 0.072310 + b * 0.986039;
  final sum = xValue + yValue + zValue;
  if (sum <= 0) return {'x': 0.3127, 'y': 0.3290};
  return {'x': xValue / sum, 'y': yValue / sum};
}

double _linear(double value) => value <= 0.04045
    ? value / 12.92
    : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
