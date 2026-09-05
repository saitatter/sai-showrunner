import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../components/data_inputs/data_input.dart';
import '../../runtime/expression.dart';
import '../iot/light_color.dart';
import '../registry/plugin_registry.dart';

typedef TwinklyRequest =
    Future<RuntimeMap> Function(
      String ip,
      String method,
      String path,
      RuntimeMap query,
      dynamic body,
    );

final class TwinklyTransport {
  const TwinklyTransport(this.request);

  final TwinklyRequest request;
}

final class TwinklyHttpTransport {
  TwinklyHttpTransport({Random? random}) : _random = random ?? Random.secure();

  final Random _random;
  final Map<String, _TwinklyToken> _tokens = {};

  Future<RuntimeMap> request(
    String ip,
    String method,
    String path,
    RuntimeMap query,
    dynamic body,
  ) async {
    final token = path == '/gestalt' ? null : await _validToken(ip);
    try {
      return await _request(ip, method, path, query, body, token);
    } on HttpException catch (error) {
      if (token != null && error.message.contains('Invalid Token')) {
        _tokens.remove(ip);
        return _request(ip, method, path, query, body, await _authenticate(ip));
      }
      rethrow;
    }
  }

  Future<RuntimeMap> _request(
    String ip,
    String method,
    String path,
    RuntimeMap query,
    dynamic body,
    String? token,
  ) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse('http://$ip/xled/v1$path').replace(
        queryParameters: {
          ...query.map((key, value) => MapEntry(key, '$value')),
        },
      );
      final request = await client.openUrl(method, uri);
      request.headers.contentType = ContentType.json;
      if (token != null) request.headers.set('X-Auth-Token', token);
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close();
      final text = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Twinkly request failed (${response.statusCode}): $text',
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

  Future<String> _validToken(String ip) async {
    final current = _tokens[ip];
    if (current != null && current.expiresAt.isAfter(DateTime.now())) {
      return current.value;
    }
    return _authenticate(ip);
  }

  Future<String> _authenticate(String ip) async {
    final challengeBytes = List<int>.generate(32, (_) => _random.nextInt(256));
    final login = await _request(ip, 'POST', '/login', const {}, {
      'challenge': base64Encode(challengeBytes),
    }, null);
    final token = login['authentication_token']?.toString().trim() ?? '';
    final response = login['challenge-response']?.toString() ?? '';
    final expiresIn = _int(login['authentication_token_expires_in']) ?? 0;
    if (token.isEmpty || response.isEmpty || expiresIn <= 0) {
      throw const FormatException('Twinkly login response is incomplete.');
    }
    await _request(ip, 'POST', '/verify', const {}, {
      'challenge-response': response,
    }, token);
    _tokens[ip] = _TwinklyToken(
      value: token,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn - 5)),
    );
    return token;
  }
}

final class _TwinklyToken {
  const _TwinklyToken({required this.value, required this.expiresAt});

  final String value;
  final DateTime expiresAt;
}

const _deviceFields = [
  DartDataInputSchema(
    label: 'Device IP',
    key: 'ip',
    kind: DartDataInputKind.text,
    required: true,
  ),
];

const _deviceSchema = DartDataInputSchema(
  label: 'Twinkly device',
  kind: DartDataInputKind.object,
  fields: _deviceFields,
);

const _colorSchema = DartDataInputSchema(
  label: 'Twinkly color',
  kind: DartDataInputKind.object,
  fields: [
    ..._deviceFields,
    DartDataInputSchema(
      label: 'Color',
      key: 'color',
      kind: DartDataInputKind.lightColor,
      required: true,
    ),
  ],
);

const _movieSchema = DartDataInputSchema(
  label: 'Twinkly movie',
  kind: DartDataInputKind.object,
  fields: [
    ..._deviceFields,
    DartDataInputSchema(
      label: 'Movie ID',
      key: 'movieId',
      kind: DartDataInputKind.text,
      required: true,
    ),
  ],
);

DartPluginManifest createTwinklyPlugin(TwinklyTransport transport) =>
    DartPluginManifest(
      id: 'twinkly',
      name: 'Twinkly',
      settings: const [
        DartSettingDefinition(
          id: 'subnetMask',
          displayName: 'Subnet Mask',
          defaultValue: '255.255.255.255',
        ),
      ],
      actions: [
        DartActionDefinition(
          pluginId: 'twinkly',
          actionId: 'getInfo',
          displayName: 'Get Device Info',
          configSchema: _deviceSchema,
          invoke: (config, context) => transport.request(
            _ip(config, context),
            'GET',
            '/gestalt',
            const {},
            null,
          ),
        ),
        DartActionDefinition(
          pluginId: 'twinkly',
          actionId: 'getMode',
          displayName: 'Get LED Mode',
          configSchema: _deviceSchema,
          invoke: (config, context) => transport.request(
            _ip(config, context),
            'GET',
            '/led/mode',
            const {},
            null,
          ),
        ),
        DartActionDefinition(
          pluginId: 'twinkly',
          actionId: 'getColor',
          displayName: 'Get LED Color',
          configSchema: _deviceSchema,
          invoke: (config, context) => transport.request(
            _ip(config, context),
            'GET',
            '/led/color',
            const {},
            null,
          ),
        ),
        DartActionDefinition(
          pluginId: 'twinkly',
          actionId: 'setColor',
          displayName: 'Set LED Color',
          configSchema: _colorSchema,
          invoke: (config, context) => _setColor(transport, config, context),
        ),
        DartActionDefinition(
          pluginId: 'twinkly',
          actionId: 'turnOff',
          displayName: 'Turn LEDs Off',
          configSchema: _deviceSchema,
          invoke: (config, context) => transport.request(
            _ip(config, context),
            'POST',
            '/led/mode',
            const {},
            {'mode': 'off', 'effect_id': 0},
          ),
        ),
        DartActionDefinition(
          pluginId: 'twinkly',
          actionId: 'listMovies',
          displayName: 'List Movies',
          configSchema: _deviceSchema,
          invoke: (config, context) => transport.request(
            _ip(config, context),
            'GET',
            '/movies',
            const {},
            null,
          ),
        ),
        DartActionDefinition(
          pluginId: 'twinkly',
          actionId: 'setMovie',
          displayName: 'Set Movie',
          configSchema: _movieSchema,
          invoke: (config, context) => _setMovie(transport, config, context),
        ),
        DartActionDefinition(
          pluginId: 'twinkly',
          actionId: 'movie',
          displayName: 'Twinkly Movie',
          configSchema: _movieSchema,
          invoke: (config, context) => _setMovie(transport, config, context),
        ),
      ],
    );

Future<Object?> _setColor(
  TwinklyTransport transport,
  RuntimeMap config,
  EvaluationContext context,
) async {
  final color = parseLightColor(config['color']?.toString());
  if (color == null || color.isKelvin) {
    throw ArgumentError('Twinkly requires an hsb(...) color.');
  }
  final ip = _ip(config, context);
  await transport.request(ip, 'POST', '/led/color', const {}, {
    'hue': color.hue!.round(),
    'saturation': (color.saturation!.clamp(0, 100) * 255 / 100).round(),
    'value': (color.brightness.clamp(0, 100) * 255 / 100).round(),
  });
  return transport.request(ip, 'POST', '/led/mode', const {}, {
    'mode': 'color',
    'effect_id': 0,
  });
}

Future<Object?> _setMovie(
  TwinklyTransport transport,
  RuntimeMap config,
  EvaluationContext context,
) async {
  final ip = _ip(config, context);
  await transport.request(ip, 'POST', '/movies/current', const {}, {
    'id': config['movieId'] ?? config['movie'],
  });
  return transport.request(ip, 'POST', '/led/mode', const {}, {
    'mode': 'movie',
    'effect_id': 0,
  });
}

String _ip(RuntimeMap config, EvaluationContext context) {
  final ip =
      (config['ip'] ?? context.contextState['ip'])?.toString().trim() ?? '';
  if (ip.isEmpty) throw ArgumentError('ip is required.');
  return ip;
}

int? _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value');
