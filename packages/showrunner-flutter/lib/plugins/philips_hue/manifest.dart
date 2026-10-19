import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../../schema/data_input.dart';
import '../../runtime/expression.dart';
import '../iot/light_color.dart';
import '../registry/plugin_contract.dart';
import 'contracts.dart';

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

const _plugSchema = DartDataInputSchema(
  label: 'Hue plug state',
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
      label: 'Power',
      key: 'state',
      kind: DartDataInputKind.enumeration,
      options: ['on', 'off', 'toggle'],
      defaultValue: 'on',
    ),
  ],
);

const _sceneSchema = DartDataInputSchema(
  label: 'Hue scene',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Group',
      key: 'group',
      kind: DartDataInputKind.resource,
      resourceType: ResourceTypeId('Light'),
    ),
    DartDataInputSchema(
      label: 'Scene ID',
      key: 'sceneId',
      kind: DartDataInputKind.text,
    ),
    DartDataInputSchema(
      label: 'Scene alias',
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
  id: PluginId('philips-hue'),
  name: 'Philips Hue',
  settings: const [
    SettingSpec(id: SettingId('hubIp'), displayName: 'Hue Hub IP'),
    SettingSpec(
      id: SettingId('hubKey'),
      displayName: 'Hue Application Key',
      secret: true,
    ),
  ],
  actions: [
    ActionSpec<HueActionConfig, RuntimeMap>(
      pluginId: PluginId('philips-hue'),
      actionId: ActionId('listLights'),
      displayName: 'List Lights',
      configCodec: hueActionConfigCodec,
      invoke: (config, context) =>
          transport.request('GET', '/resource/light', const {}, null),
    ),
    ActionSpec<HueActionConfig, RuntimeMap>(
      pluginId: PluginId('philips-hue'),
      actionId: ActionId('listGroups'),
      displayName: 'List Light Groups',
      configCodec: hueActionConfigCodec,
      invoke: (config, context) =>
          transport.request('GET', '/resource/grouped_light', const {}, null),
    ),
    ActionSpec<HueActionConfig, RuntimeMap>(
      pluginId: PluginId('philips-hue'),
      actionId: ActionId('listScenes'),
      displayName: 'List Scenes',
      configCodec: hueActionConfigCodec,
      invoke: (config, context) =>
          transport.request('GET', '/resource/scene', const {}, null),
    ),
    ActionSpec<HueActionConfig, RuntimeMap>(
      pluginId: PluginId('philips-hue'),
      actionId: ActionId('setLightState'),
      displayName: 'Set Light State',
      configSchema: _deviceSchema,
      configCodec: hueActionConfigCodec,
      invoke: (config, context) => _setLightState(
        transportResolver?.call(config.toRuntime()) ?? transport,
        config,
        context,
      ),
    ),
    ActionSpec<HueActionConfig, RuntimeMap>(
      pluginId: PluginId('philips-hue'),
      actionId: ActionId('setPlugState'),
      displayName: 'Set Plug State',
      configSchema: _plugSchema,
      configCodec: hueActionConfigCodec,
      invoke: (config, context) => _setPlugState(
        transportResolver?.call(config.toRuntime()) ?? transport,
        config,
      ),
    ),
    ActionSpec<HueActionConfig, RuntimeMap>(
      pluginId: PluginId('philips-hue'),
      actionId: ActionId('recallScene'),
      displayName: 'Recall Hue Scene',
      configSchema: _sceneSchema,
      configCodec: hueActionConfigCodec,
      invoke: (config, context) => _recallScene(
        transportResolver?.call(config.toRuntime()) ?? transport,
        config,
      ),
    ),
    ActionSpec<HueActionConfig, RuntimeMap>(
      pluginId: PluginId('philips-hue'),
      actionId: ActionId('scene'),
      displayName: 'Set HUE Scene',
      configSchema: _sceneSchema,
      configCodec: hueActionConfigCodec,
      invoke: (config, context) => _recallScene(
        transportResolver?.call(config.toRuntime()) ?? transport,
        config,
      ),
    ),
  ],
);

Future<RuntimeMap> _recallScene(
  HueTransport transport,
  HueActionConfig config,
) => transport.request(
  'PUT',
  '/resource/scene/${_requiredScene(config.sceneId, config.scene)}',
  const {},
  {
    'recall': {'action': 'active'},
  },
);

Future<RuntimeMap> _setLightState(
  HueTransport transport,
  HueActionConfig config,
  EvaluationContext context,
) async {
  final resourceType = config.resourceType ?? 'light';
  final lightId = _required(config.lightId, 'lightId');
  var power = config.power ?? HuePowerMode.enabled;
  if (power == HuePowerMode.toggle) {
    final current = await transport.request(
      'GET',
      '/resource/$resourceType/$lightId',
      const {},
      null,
    );
    power = _isOn(current) ? HuePowerMode.disabled : HuePowerMode.enabled;
  }
  final body = <String, dynamic>{
    'on': {'on': power == HuePowerMode.enabled},
    'dynamics': {
      'duration':
          ((_number(config.transitionSeconds, 0.5)).clamp(0, 600) * 1000)
              .round(),
    },
  };
  final parsedColor = parseLightColor(config.color);
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

Future<RuntimeMap> _setPlugState(
  HueTransport transport,
  HueActionConfig config,
) async {
  var power = config.power ?? HuePowerMode.enabled;
  final lightId = _required(config.lightId, 'lightId');
  if (power == HuePowerMode.toggle) {
    final current = await transport.request(
      'GET',
      '/resource/light/$lightId',
      const {},
      null,
    );
    power = _isOn(current) ? HuePowerMode.disabled : HuePowerMode.enabled;
  }
  return transport.request('PUT', '/resource/light/$lightId', const {}, {
    'on': {'on': power == HuePowerMode.enabled},
  });
}

String _required(String? value, String key) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) throw ArgumentError('$key is required.');
  return text;
}

String _requiredScene(String? sceneId, String? sceneAlias) {
  final scene = (sceneId ?? sceneAlias)?.trim() ?? '';
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
