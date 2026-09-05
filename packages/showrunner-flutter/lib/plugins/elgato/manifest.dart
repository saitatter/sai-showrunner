import 'dart:convert';
import 'dart:io';

import '../../components/data_inputs/data_input.dart';
import '../../runtime/expression.dart';
import '../iot/light_color.dart';
import '../registry/plugin_registry.dart';

typedef ElgatoRequest =
    Future<RuntimeMap> Function(String method, String path, dynamic body);

final class ElgatoTransport {
  const ElgatoTransport(this.request);

  final ElgatoRequest request;
}

typedef ElgatoTransportResolver = ElgatoTransport Function(RuntimeMap config);

final class ElgatoHttpTransport {
  const ElgatoHttpTransport({required this.host, this.port = 9123});

  final String host;
  final int port;

  Future<RuntimeMap> request(String method, String path, dynamic body) async {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final uri = Uri(
      scheme: 'http',
      host: host,
      port: port,
      path: '/elgato$normalizedPath',
    );
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, uri);
      request.headers.contentType = ContentType.json;
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close();
      final text = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Elgato request failed (${response.statusCode}): $text',
        );
      }
      if (text.isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(text);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } finally {
      client.close(force: true);
    }
  }
}

const _lightSchema = DartDataInputSchema(
  label: 'Elgato light state',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Power',
      key: 'state',
      kind: DartDataInputKind.enumeration,
      options: ['on', 'off', 'toggle'],
      defaultValue: 'on',
    ),
    DartDataInputSchema(
      label: 'Device IP / Host',
      key: 'host',
      kind: DartDataInputKind.text,
    ),
    DartDataInputSchema(
      label: 'Device Port',
      key: 'port',
      kind: DartDataInputKind.number,
      defaultValue: 9123,
    ),
    DartDataInputSchema(
      label: 'Color',
      key: 'color',
      kind: DartDataInputKind.lightColor,
    ),
    DartDataInputSchema(
      label: 'Number of lights',
      key: 'numberOfLights',
      kind: DartDataInputKind.number,
      defaultValue: 1,
    ),
  ],
);

DartPluginManifest createElgatoPlugin(
  ElgatoTransport transport, {
  bool supportsRgb = false,
  int numberOfLights = 1,
  ElgatoTransportResolver? transportResolver,
}) => DartPluginManifest(
  id: 'elgato',
  name: 'Elgato',
  settings: const [
    DartSettingDefinition(id: 'host', displayName: 'Device IP / Host'),
    DartSettingDefinition(
      id: 'port',
      displayName: 'Device Port',
      defaultValue: 9123,
    ),
    DartSettingDefinition(
      id: 'numberOfLights',
      displayName: 'Number of Lights',
      defaultValue: 1,
    ),
    DartSettingDefinition(
      id: 'rgb',
      displayName: 'RGB / Light Strip',
      defaultValue: false,
    ),
  ],
  actions: [
    DartActionDefinition(
      pluginId: 'elgato',
      actionId: 'getInfo',
      displayName: 'Get Accessory Info',
      invoke: (config, context) =>
          transport.request('GET', '/accessory-info', null),
    ),
    DartActionDefinition(
      pluginId: 'elgato',
      actionId: 'getLights',
      displayName: 'Get Light State',
      invoke: (config, context) => transport.request('GET', '/lights', null),
    ),
    DartActionDefinition(
      pluginId: 'elgato',
      actionId: 'setLightState',
      displayName: 'Set Light State',
      configSchema: _lightSchema,
      invoke: (config, context) => _setLightState(
        transportResolver?.call(config) ?? transport,
        config,
        supportsRgb: supportsRgb,
        defaultNumberOfLights: numberOfLights,
      ),
    ),
  ],
);

Future<Object?> _setLightState(
  ElgatoTransport transport,
  RuntimeMap config, {
  required bool supportsRgb,
  required int defaultNumberOfLights,
}) async {
  final current = await transport.request('GET', '/lights', null);
  final currentLight = _firstLight(current);
  var power = config['state'] ?? 'on';
  if (power == 'toggle') power = currentLight?['on'] != true;
  final color =
      parseLightColor(config['color']?.toString()) ??
      _colorFromLight(currentLight);
  if (color == null) {
    throw ArgumentError('Elgato did not return a usable light color.');
  }
  final light = <String, dynamic>{
    'on': power == true || power == 'on',
    'brightness': color.brightness.clamp(0, 100).round(),
  };
  if (color.isKelvin) {
    light['temperature'] = kelvinToElgato(color.kelvin!);
  } else {
    if (!supportsRgb) {
      return {
        'updated': false,
        'reason': 'RGB is not enabled for this Elgato accessory.',
      };
    }
    light['hue'] = color.hue!.clamp(0, 360).round();
    light['saturation'] = color.saturation!.clamp(0, 100).round();
  }
  final count = _positiveInt(config['numberOfLights'], defaultNumberOfLights);
  final response = await transport.request('PUT', '/lights', {
    'numberOfLights': count,
    'lights': List.generate(count, (_) => Map<String, dynamic>.from(light)),
  });
  return {'updated': true, 'state': light, ...response};
}

Map<String, dynamic>? _firstLight(RuntimeMap response) {
  final lights = response['lights'];
  if (lights is List && lights.isNotEmpty && lights.first is Map) {
    return Map<String, dynamic>.from(lights.first as Map);
  }
  return null;
}

LightColorValue? _colorFromLight(Map<String, dynamic>? light) {
  if (light == null) return null;
  final brightness = _number(light['brightness'], 100);
  final temperature = light['temperature'];
  if (temperature is num) {
    return LightColorValue.kelvin(
      kelvin: elgatoToKelvin(temperature.toDouble()).toDouble(),
      brightness: brightness,
    );
  }
  final hue = light['hue'];
  final saturation = light['saturation'];
  if (hue is num && saturation is num) {
    return LightColorValue.hsb(
      hue: hue.toDouble(),
      saturation: saturation.toDouble(),
      brightness: brightness,
    );
  }
  return null;
}

double _number(Object? value, double fallback) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? fallback;

int _positiveInt(Object? value, int fallback) {
  final number = value is num ? value.toInt() : int.tryParse('$value');
  return number != null && number > 0 ? number : fallback.clamp(1, 64).toInt();
}

int elgatoToKelvin(double value) => ((-4100 * value + 1993300) / 201).round();

int kelvinToElgato(double kelvin) =>
    ((kelvin - 1993300 / 201) * 201 / -4100).round().clamp(143, 344);
