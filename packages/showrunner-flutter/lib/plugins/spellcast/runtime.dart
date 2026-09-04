import '../../runtime/expression.dart';
import '../../services/http_provider_transports.dart';
import '../../services/showrunner_data_service.dart';

typedef SpellcastRequest =
    Future<dynamic> Function(
      String method,
      String path,
      RuntimeMap query,
      dynamic body,
    );

final class SpellcastRemoteSpell {
  const SpellcastRemoteSpell({
    required this.id,
    required this.name,
    required this.description,
    required this.bits,
    required this.color,
    required this.enabled,
    this.connected = false,
  });

  final String id;
  final String name;
  final String description;
  final int bits;
  final String color;
  final bool enabled;
  final bool connected;

  factory SpellcastRemoteSpell.fromJson(dynamic value) {
    if (value is! Map) {
      throw const FormatException('Spellcast response must contain objects.');
    }
    final json = Map<String, dynamic>.from(value);
    final id = (json['_id'] ?? json['id'])?.toString() ?? '';
    final name = json['name']?.toString() ?? '';
    if (id.isEmpty || name.isEmpty) {
      throw const FormatException('Spellcast spell requires an id and name.');
    }
    return SpellcastRemoteSpell(
      id: id,
      name: name,
      description: json['description']?.toString() ?? '',
      bits: (json['bits'] as num?)?.round() ?? 10,
      color: json['color']?.toString() ?? '#719ece',
      enabled: json['enabled'] as bool? ?? false,
      connected: json['connected'] as bool? ?? false,
    );
  }

  RuntimeMap toJson() => {
    '_id': id,
    'name': name,
    'description': description,
    'bits': bits,
    'color': color,
    'enabled': enabled,
    'connected': connected,
  };
}

final class SpellcastService {
  SpellcastService({required this.dataService, this.request});

  final ShowRunnerDataService dataService;
  final SpellcastRequest? request;

  Future<List<SpellcastRemoteSpell>> listSpells() async {
    final settings = await _settings();
    final raw = await _send(
      'GET',
      '/streams/${_streamId(settings)}/buttons/',
      const {},
      null,
      settings,
    );
    final values = raw is List
        ? raw
        : raw is Map && raw['items'] is List
        ? raw['items'] as List
        : const <dynamic>[];
    final spells = <SpellcastRemoteSpell>[];
    for (final value in values) {
      try {
        spells.add(SpellcastRemoteSpell.fromJson(value));
      } on FormatException {
        // Ignore malformed remote items and keep the rest of the catalog.
      }
    }
    return spells;
  }

  Future<SpellcastRemoteSpell> createSpell({
    required String name,
    required String description,
    required int bits,
    required String color,
    required bool enabled,
  }) async {
    final settings = await _settings();
    final raw = await _send(
      'POST',
      '/streams/${_streamId(settings)}/buttons',
      const {},
      {
        'name': name,
        'description': description,
        'bits': bits,
        'color': color,
        'enabled': enabled,
      },
      settings,
    );
    return SpellcastRemoteSpell.fromJson(_unwrapItem(raw));
  }

  Future<SpellcastRemoteSpell> updateSpell(
    String id, {
    String? name,
    String? description,
    int? bits,
    String? color,
    bool? enabled,
  }) async {
    final settings = await _settings();
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (description != null) body['description'] = description;
    if (bits != null) body['bits'] = bits;
    if (color != null) body['color'] = color;
    if (enabled != null) body['enabled'] = enabled;
    final raw = await _send(
      'PUT',
      '/streams/${_streamId(settings)}/buttons/${Uri.encodeComponent(id)}',
      const {},
      body,
      settings,
    );
    return SpellcastRemoteSpell.fromJson(_unwrapItem(raw));
  }

  Future<void> deleteSpell(String id) async {
    final settings = await _settings();
    await _send(
      'DELETE',
      '/streams/${_streamId(settings)}/buttons/${Uri.encodeComponent(id)}',
      const {},
      null,
      settings,
    );
  }

  Future<RuntimeMap> _settings() async {
    final settings = await dataService.loadPluginSettings('twitch');
    final token = settings['accessToken']?.toString() ?? '';
    final streamId = _streamId(settings);
    if (token.isEmpty || streamId.isEmpty) {
      throw StateError(
        'Twitch access token and broadcaster ID are required for Spellcast.',
      );
    }
    return settings;
  }

  Future<dynamic> _send(
    String method,
    String path,
    RuntimeMap query,
    dynamic body,
    RuntimeMap settings,
  ) {
    final custom = request;
    if (custom != null) return custom(method, path, query, body);
    final transport = JsonHttpTransport(
      baseUrl: 'https://api.spellcast.gg/',
      accessToken: settings['accessToken']?.toString(),
    );
    return transport.requestValue(method, path, query, body);
  }
}

String _streamId(RuntimeMap settings) =>
    settings['broadcasterId']?.toString() ??
    settings['channelId']?.toString() ??
    '';

dynamic _unwrapItem(dynamic raw) {
  if (raw is Map && raw['item'] != null) return raw['item'];
  if (raw is Map && raw['data'] is Map) return raw['data'];
  return raw;
}
