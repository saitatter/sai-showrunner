import '../../schema/data_input.dart';
import '../../runtime/expression.dart';
import '../iot/light_color.dart';
import '../registry/plugin_contract.dart';
import 'contracts.dart';

typedef GoveeRequest =
    Future<RuntimeMap> Function(
      String method,
      String path,
      RuntimeMap query,
      dynamic body,
    );

final class GoveeTransport {
  const GoveeTransport(this.request);

  final GoveeRequest request;
}

const _deviceSchema = DartDataInputSchema(
  label: 'Govee device',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Device ID / MAC',
      key: 'device',
      kind: DartDataInputKind.text,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Model',
      key: 'model',
      kind: DartDataInputKind.text,
      required: true,
    ),
  ],
);

const _powerSchema = DartDataInputSchema(
  label: 'Govee power',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Device ID / MAC',
      key: 'device',
      kind: DartDataInputKind.text,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Model',
      key: 'model',
      kind: DartDataInputKind.text,
      required: true,
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

const _colorSchema = DartDataInputSchema(
  label: 'Govee color',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Device ID / MAC',
      key: 'device',
      kind: DartDataInputKind.text,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Model',
      key: 'model',
      kind: DartDataInputKind.text,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Color',
      key: 'color',
      kind: DartDataInputKind.lightColor,
      required: true,
    ),
  ],
);

const _brightnessSchema = DartDataInputSchema(
  label: 'Govee brightness',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Device ID / MAC',
      key: 'device',
      kind: DartDataInputKind.text,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Model',
      key: 'model',
      kind: DartDataInputKind.text,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Brightness',
      key: 'brightness',
      kind: DartDataInputKind.number,
      required: true,
      defaultValue: 100,
    ),
  ],
);

DartPluginManifest createGoveePlugin(GoveeTransport transport) =>
    DartPluginManifest(
      id: PluginId('govee'),
      name: 'Govee',
      settings: const [
        SettingSpec(
          id: SettingId('apiKey'),
          displayName: 'Govee API Key',
          secret: true,
        ),
      ],
      actions: [
        ActionSpec<GoveeDeviceConfig, RuntimeMap>(
          pluginId: PluginId('govee'),
          actionId: ActionId('listDevices'),
          displayName: 'List Devices',
          configCodec: goveeDeviceConfigCodec,
          invoke: (config, context) =>
              transport.request('GET', '/v1/devices', const {}, null),
        ),
        ActionSpec<GoveeDeviceConfig, RuntimeMap>(
          pluginId: PluginId('govee'),
          actionId: ActionId('getDeviceState'),
          displayName: 'Get Device State',
          configSchema: _deviceSchema,
          configCodec: goveeDeviceConfigCodec,
          invoke: (config, context) => transport.request(
            'GET',
            '/v1/devices/state',
            _deviceQuery(config, context),
            null,
          ),
        ),
        ActionSpec<GoveeDeviceConfig, RuntimeMap>(
          pluginId: PluginId('govee'),
          actionId: ActionId('setPower'),
          displayName: 'Set Power',
          configSchema: _powerSchema,
          configCodec: goveeDeviceConfigCodec,
          invoke: (config, context) => _setPower(transport, config, context),
        ),
        ActionSpec<GoveeDeviceConfig, RuntimeMap>(
          pluginId: PluginId('govee'),
          actionId: ActionId('setColor'),
          displayName: 'Set Color',
          configSchema: _colorSchema,
          configCodec: goveeDeviceConfigCodec,
          invoke: (config, context) => _setColor(transport, config, context),
        ),
        ActionSpec<GoveeDeviceConfig, RuntimeMap>(
          pluginId: PluginId('govee'),
          actionId: ActionId('setBrightness'),
          displayName: 'Set Brightness',
          configSchema: _brightnessSchema,
          configCodec: goveeDeviceConfigCodec,
          invoke: (config, context) =>
              transport.request('PUT', '/v1/devices/control', const {}, {
                ..._deviceBody(config, context),
                'cmd': {
                  'name': 'brightness',
                  'value': _brightness(config.brightness),
                },
              }),
        ),
      ],
    );

Future<RuntimeMap> _setPower(
  GoveeTransport transport,
  GoveeDeviceConfig config,
  EvaluationContext context,
) async {
  var power = config.power ?? GoveePowerMode.enabled;
  if (power == GoveePowerMode.toggle) {
    final response = await transport.request(
      'GET',
      '/v1/devices/state',
      _deviceQuery(config, context),
      null,
    );
    power = _powerState(response)
        ? GoveePowerMode.disabled
        : GoveePowerMode.enabled;
  }
  return transport.request('PUT', '/v1/devices/control', const {}, {
    ..._deviceBody(config, context),
    'cmd': {
      'name': 'turn',
      'value': power == GoveePowerMode.enabled ? 'on' : 'off',
    },
  });
}

Future<RuntimeMap> _setColor(
  GoveeTransport transport,
  GoveeDeviceConfig config,
  EvaluationContext context,
) async {
  final parsed = parseLightColor(config.color);
  if (parsed == null) {
    throw ArgumentError('A valid hsb(...) or kb(...) color is required.');
  }

  if (parsed.isKelvin) {
    await transport.request('PUT', '/v1/devices/control', const {}, {
      ..._deviceBody(config, context),
      'cmd': {'name': 'colorTem', 'value': parsed.kelvin!.round()},
    });
  } else {
    await transport.request('PUT', '/v1/devices/control', const {}, {
      ..._deviceBody(config, context),
      'cmd': {'name': 'color', 'value': _rgb(parsed)},
    });
  }
  return transport.request('PUT', '/v1/devices/control', const {}, {
    ..._deviceBody(config, context),
    'cmd': {'name': 'brightness', 'value': _brightness(parsed.brightness)},
  });
}

RuntimeMap _deviceQuery(GoveeDeviceConfig config, EvaluationContext context) =>
    {
      'device': _deviceValue(config.device, context, 'device'),
      'model': _deviceValue(config.model, context, 'model'),
    };

RuntimeMap _deviceBody(GoveeDeviceConfig config, EvaluationContext context) => {
  'device': _deviceValue(config.device, context, 'device'),
  'model': _deviceValue(config.model, context, 'model'),
};

String _deviceValue(String? value, EvaluationContext context, String key) =>
    (value ?? context.contextState[key])?.toString().trim() ?? '';

int _brightness(Object? value) =>
    ((value is num ? value : double.tryParse('$value') ?? 100).clamp(
      0,
      100,
    )).round();

bool _powerState(RuntimeMap response) {
  final data = response['data'];
  final properties = data is Map ? data['properties'] : null;
  if (properties is List) {
    for (final property in properties.whereType<Map>()) {
      if (property['powerState'] != null) {
        return property['powerState'].toString().toLowerCase() == 'on';
      }
    }
  }
  return false;
}

Map<String, int> _rgb(LightColorValue value) {
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
  return {
    'r': ((red + match) * 255).round().clamp(0, 255),
    'g': ((green + match) * 255).round().clamp(0, 255),
    'b': ((blue + match) * 255).round().clamp(0, 255),
  };
}
