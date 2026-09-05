import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

import '../../schema/data_input.dart';
import '../../runtime/expression.dart';
import '../iot/light_color.dart';
import '../registry/plugin_contract.dart';

typedef WyzeToken = ({String accessToken, String refreshToken});

abstract interface class WyzeTransport {
  Future<WyzeToken> login(String email, String password);

  Future<List<RuntimeMap>> getDevices();

  Future<RuntimeMap> getDeviceState(String mac, String model);

  Future<RuntimeMap> setLightState(
    String mac,
    String model,
    RuntimeMap properties,
  );

  Future<RuntimeMap> setPlugState(String mac, String model, bool on);

  Future<void> close();
}

final class CallbackWyzeTransport implements WyzeTransport {
  const CallbackWyzeTransport({
    required this.loginCallback,
    required this.getDevicesCallback,
    required this.getDeviceStateCallback,
    required this.setLightStateCallback,
    required this.setPlugStateCallback,
    this.closeCallback,
  });

  final Future<WyzeToken> Function(String email, String password) loginCallback;
  final Future<List<RuntimeMap>> Function() getDevicesCallback;
  final Future<RuntimeMap> Function(String mac, String model)
  getDeviceStateCallback;
  final Future<RuntimeMap> Function(
    String mac,
    String model,
    RuntimeMap properties,
  )
  setLightStateCallback;
  final Future<RuntimeMap> Function(String mac, String model, bool on)
  setPlugStateCallback;
  final Future<void> Function()? closeCallback;

  @override
  Future<WyzeToken> login(String email, String password) =>
      loginCallback(email, password);

  @override
  Future<List<RuntimeMap>> getDevices() => getDevicesCallback();

  @override
  Future<RuntimeMap> getDeviceState(String mac, String model) =>
      getDeviceStateCallback(mac, model);

  @override
  Future<RuntimeMap> setLightState(
    String mac,
    String model,
    RuntimeMap properties,
  ) => setLightStateCallback(mac, model, properties);

  @override
  Future<RuntimeMap> setPlugState(String mac, String model, bool on) =>
      setPlugStateCallback(mac, model, on);

  @override
  Future<void> close() async => closeCallback?.call();
}

final class WyzeHttpTransport implements WyzeTransport {
  WyzeHttpTransport({
    required this.keyId,
    required this.apiKey,
    this.accessToken,
    this.refreshToken,
    this.apiBase = 'https://api.wyzecam.com',
    this.authBase = 'https://auth-prod.api.wyze.com',
    this.onTokens,
  });

  final String keyId;
  final String apiKey;
  final String apiBase;
  final String authBase;
  final Future<void> Function(WyzeToken tokens)? onTokens;
  String? accessToken;
  String? refreshToken;

  @override
  Future<WyzeToken> login(String email, String password) async {
    if (keyId.trim().isEmpty || apiKey.trim().isEmpty) {
      throw StateError('Wyze Key ID and API Key are required.');
    }
    final response = await _post(
      '$authBase/api/user/login',
      {'email': email, 'password': _tripleMd5(password)},
      headers: {
        'Keyid': keyId,
        'Apikey': apiKey,
        'User-Agent': 'wyze_ios_2.21.35',
        'phone-id': 'wyze_developer_api',
      },
    );
    final tokens = _tokens(response);
    if (tokens == null) throw StateError('Wyze login response is incomplete.');
    await _applyTokens(tokens);
    return tokens;
  }

  @override
  Future<List<RuntimeMap>> getDevices() async {
    final response = await _apiRequest(
      '/app/v2/home_page/get_object_list',
      const {},
    );
    final data = response['data'];
    final devices = data is Map ? data['device_list'] : null;
    return devices is List
        ? devices
              .whereType<Map>()
              .map((device) => Map<String, dynamic>.from(device))
              .toList()
        : const [];
  }

  @override
  Future<RuntimeMap> getDeviceState(String mac, String model) async {
    final response = await _apiRequest('/app/v2/device/get_device_info', {
      'device_mac': mac,
      'device_model': model,
    });
    final data = response['data'];
    if (data is! Map) return <String, dynamic>{};
    final state = <String, dynamic>{};
    final properties = data['property_list'];
    if (properties is List) {
      for (final property in properties.whereType<Map>()) {
        final id = property['pid']?.toString();
        final value = property['value'];
        switch (id) {
          case 'P3':
            state['power'] = value == true || value.toString() == '1';
          case 'P1507':
            state['color'] = value;
          case 'P1501':
            state['brightness'] = _number(value);
          case 'P1502':
            state['colorTemp'] = _number(value);
        }
      }
    }
    return state;
  }

  @override
  Future<RuntimeMap> setLightState(
    String mac,
    String model,
    RuntimeMap properties,
  ) => _runAction(mac, model, 'set_mesh_property', properties);

  @override
  Future<RuntimeMap> setPlugState(String mac, String model, bool on) =>
      _runAction(mac, model, on ? 'power_on' : 'power_off', null);

  @override
  Future<void> close() async {}

  Future<RuntimeMap> _runAction(
    String mac,
    String model,
    String action,
    RuntimeMap? properties,
  ) => _apiRequest('/app/v2/auto/run_action', {
    'provider_key': model,
    'instance_id': mac,
    'action_key': action,
    'action_params': {
      'list': [
        {
          'mac': mac,
          'plist': properties == null ? [] : _properties(properties),
        },
      ],
    },
    'custom_string': '',
  });

  Future<RuntimeMap> _apiRequest(String path, RuntimeMap data) async {
    final token = accessToken?.trim();
    if (token == null || token.isEmpty) {
      throw StateError('Wyze account is not authenticated.');
    }
    var response = await _post(
      '$apiBase$path',
      _requestBody({'access_token': token, ...data}),
    );
    if (_isAccessTokenError(response) && refreshToken?.isNotEmpty == true) {
      final refreshed = await _refresh();
      response = await _post(
        '$apiBase$path',
        _requestBody({'access_token': refreshed.accessToken, ...data}),
      );
    }
    if (_isAccessTokenError(response)) {
      throw StateError('Wyze access token is invalid.');
    }
    return response;
  }

  Future<WyzeToken> _refresh() async {
    final response = await _post(
      '$apiBase/app/user/refresh_token',
      _requestBody({'refresh_token': refreshToken}),
    );
    final tokens = _tokens(response);
    if (tokens == null) throw StateError('Wyze token refresh failed.');
    await _applyTokens(tokens);
    return tokens;
  }

  Future<void> _applyTokens(WyzeToken tokens) async {
    accessToken = tokens.accessToken;
    refreshToken = tokens.refreshToken;
    await onTokens?.call(tokens);
  }

  Future<RuntimeMap> _post(
    String url,
    RuntimeMap body, {
    Map<String, String> headers = const {},
  }) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse(url));
      request.headers.contentType = ContentType.json;
      headers.forEach(request.headers.set);
      request.write(jsonEncode(body));
      final response = await request.close();
      final text = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Wyze request failed (${response.statusCode}): $text',
        );
      }
      final decoded = text.isEmpty ? null : jsonDecode(text);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } finally {
      client.close(force: true);
    }
  }
}

const _deviceSchema = DartDataInputSchema(
  label: 'Wyze device',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'MAC / Device ID',
      key: 'device',
      kind: DartDataInputKind.text,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Product model',
      key: 'model',
      kind: DartDataInputKind.text,
      required: true,
    ),
  ],
);

const _lightSchema = DartDataInputSchema(
  label: 'Wyze light state',
  kind: DartDataInputKind.object,
  fields: [
    ..._deviceSchemaFields,
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
  ],
);

const _plugSchema = DartDataInputSchema(
  label: 'Wyze plug state',
  kind: DartDataInputKind.object,
  fields: [
    ..._deviceSchemaFields,
    DartDataInputSchema(
      label: 'Power',
      key: 'state',
      kind: DartDataInputKind.enumeration,
      options: ['on', 'off', 'toggle'],
      defaultValue: 'on',
    ),
  ],
);

const _deviceSchemaFields = [
  DartDataInputSchema(
    label: 'MAC / Device ID',
    key: 'device',
    kind: DartDataInputKind.text,
    required: true,
  ),
  DartDataInputSchema(
    label: 'Product model',
    key: 'model',
    kind: DartDataInputKind.text,
    required: true,
  ),
];

const _loginSchema = DartDataInputSchema(
  label: 'Wyze login',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Email',
      key: 'email',
      kind: DartDataInputKind.text,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Password',
      key: 'password',
      kind: DartDataInputKind.text,
      required: true,
      secret: true,
    ),
  ],
);

DartPluginManifest createWyzePlugin(WyzeTransport transport) =>
    DartPluginManifest(
      id: 'wyze',
      name: 'Wyze',
      settings: const [
        DartSettingDefinition(
          id: 'keyId',
          displayName: 'Wyze Key ID',
          secret: true,
        ),
        DartSettingDefinition(
          id: 'apiKey',
          displayName: 'Wyze API Key',
          secret: true,
        ),
        DartSettingDefinition(id: 'email', displayName: 'Wyze Email'),
        DartSettingDefinition(
          id: 'accessToken',
          displayName: 'Access Token',
          secret: true,
        ),
        DartSettingDefinition(
          id: 'refreshToken',
          displayName: 'Refresh Token',
          secret: true,
        ),
      ],
      states: const [
        DartPluginStateDefinition(
          id: 'authentication',
          displayName: 'Authentication',
          initialValue: 'configured',
        ),
      ],
      actions: [
        DartActionDefinition(
          pluginId: 'wyze',
          actionId: 'login',
          displayName: 'Login',
          configSchema: _loginSchema,
          invoke: (config, context) => _login(transport, config),
        ),
        DartActionDefinition(
          pluginId: 'wyze',
          actionId: 'listDevices',
          displayName: 'List Devices',
          invoke: (config, context) => transport.getDevices(),
        ),
        DartActionDefinition(
          pluginId: 'wyze',
          actionId: 'getDeviceState',
          displayName: 'Get Device State',
          configSchema: _deviceSchema,
          invoke: (config, context) =>
              transport.getDeviceState(_device(config), _model(config)),
        ),
        DartActionDefinition(
          pluginId: 'wyze',
          actionId: 'setLightState',
          displayName: 'Set Light State',
          configSchema: _lightSchema,
          invoke: (config, context) => _setLightState(transport, config),
        ),
        DartActionDefinition(
          pluginId: 'wyze',
          actionId: 'setPlugState',
          displayName: 'Set Plug State',
          configSchema: _plugSchema,
          invoke: (config, context) => _setPlugState(transport, config),
        ),
      ],
      dispose: transport.close,
    );

Future<Object?> _login(WyzeTransport transport, RuntimeMap config) async {
  final email = config['email']?.toString().trim() ?? '';
  final password = config['password']?.toString() ?? '';
  if (email.isEmpty || password.isEmpty) {
    return {
      'authenticated': false,
      'reason': 'Email and password are required.',
    };
  }
  await transport.login(email, password);
  return {'authenticated': true};
}

Future<Object?> _setLightState(
  WyzeTransport transport,
  RuntimeMap config,
) async {
  var state = config['state'] ?? 'on';
  if (state == 'toggle') {
    final current = await transport.getDeviceState(
      _device(config),
      _model(config),
    );
    state = current['power'] != true;
  }
  final properties = <String, dynamic>{'power': state == true || state == 'on'};
  final color = parseLightColor(config['color']?.toString());
  if (color != null) {
    properties['brightness'] = color.brightness.round().clamp(0, 100);
    if (color.isKelvin) {
      properties['colorTemp'] = color.kelvin!.round().clamp(1800, 6500);
    } else {
      properties['color'] = _hsvHex(color);
    }
  }
  final response = await transport.setLightState(
    _device(config),
    _model(config),
    properties,
  );
  return {'updated': true, ...response};
}

Future<Object?> _setPlugState(
  WyzeTransport transport,
  RuntimeMap config,
) async {
  var state = config['state'] ?? 'on';
  if (state == 'toggle') {
    final current = await transport.getDeviceState(
      _device(config),
      _model(config),
    );
    state = current['power'] != true;
  }
  final response = await transport.setPlugState(
    _device(config),
    _model(config),
    state == true || state == 'on',
  );
  return {'updated': true, ...response};
}

String _device(RuntimeMap config) {
  final value = config['device']?.toString().trim() ?? '';
  if (value.isEmpty) throw ArgumentError('device is required.');
  return value;
}

String _model(RuntimeMap config) {
  final value = config['model']?.toString().trim() ?? '';
  if (value.isEmpty) throw ArgumentError('model is required.');
  return value;
}

WyzeToken? _tokens(RuntimeMap response) {
  final source = response['data'] is Map
      ? Map<String, dynamic>.from(response['data'] as Map)
      : response;
  final access = source['access_token']?.toString().trim() ?? '';
  final refresh = source['refresh_token']?.toString().trim() ?? '';
  return access.isEmpty || refresh.isEmpty
      ? null
      : (accessToken: access, refreshToken: refresh);
}

bool _isAccessTokenError(RuntimeMap response) =>
    response['msg']?.toString() == 'AccessTokenError';

RuntimeMap _requestBody(RuntimeMap data) => {
  'phone_id': 'wyze_developer_api',
  'app_ver': 'wyze_developer_api',
  'sc': 'wyze_developer_api',
  'sv': 'wyze_developer_api',
  'ts': DateTime.now().millisecondsSinceEpoch ~/ 1000,
  ...data,
};

List<Map<String, String>> _properties(RuntimeMap properties) => [
  for (final entry in properties.entries)
    {
      'pid': _propertyId(entry.key),
      'pvalue': entry.value is bool
          ? (entry.value == true ? '1' : '0')
          : '${entry.value}',
    },
];

String _propertyId(String key) => switch (key) {
  'power' => 'P3',
  'color' => 'P1507',
  'brightness' => 'P1501',
  'colorTemp' => 'P1502',
  _ => key,
};

String _tripleMd5(String value) {
  var current = value;
  for (var iteration = 0; iteration < 3; iteration++) {
    current = md5.convert(utf8.encode(current)).toString();
  }
  return current;
}

double _number(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

String _hsvHex(LightColorValue color) {
  final hue = (color.hue! % 360 + 360) % 360;
  final saturation = color.saturation!.clamp(0, 100) / 100;
  final brightness = color.brightness.clamp(0, 100) / 100;
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
  return [red + match, green + match, blue + match]
      .map(
        (value) => (value * 255)
            .round()
            .clamp(0, 255)
            .toRadixString(16)
            .padLeft(2, '0'),
      )
      .join();
}
