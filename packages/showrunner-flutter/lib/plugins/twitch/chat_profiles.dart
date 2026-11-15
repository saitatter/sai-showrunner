import '../../runtime/expression.dart';
import '../../services/showrunner_data_service.dart';
import '../runtime/provider_operation_policy.dart';
import 'account_runtime.dart';
import 'actions.dart';
import 'connection_factory.dart';

String? twitchProfileImage(Object? value) {
  if (value is! String || value.length > 2048) return null;
  final uri = Uri.tryParse(value);
  return uri != null &&
          uri.scheme == 'https' &&
          uri.host == 'static-cdn.jtvnw.net' &&
          uri.userInfo.isEmpty &&
          (!uri.hasPort || uri.port == 443)
      ? value
      : null;
}

String twitchBadgeChannel(RuntimeMap source, String fallback) =>
    (source['source_broadcaster_user_id'] ??
            source['broadcaster_user_id'] ??
            fallback)
        .toString();

List<({String set, String version})> twitchBadgeReferences(RuntimeMap source) {
  final badges =
      source['source_badges'] ?? source['badgeVersions'] ?? source['badges'];
  if (badges is! List) return const [];
  return [
    for (final badge in badges.take(16).whereType<Map>())
      if (badge['set_id'] is String && badge['id'] is String)
        (set: badge['set_id'] as String, version: badge['id'] as String),
  ];
}

final class TwitchPublicProfile {
  const TwitchPublicProfile({
    required this.id,
    required this.name,
    required this.login,
    this.avatarUrl,
  });
  final String id, name, login;
  final String? avatarUrl;
}

final class TwitchPublicBadge {
  const TwitchPublicBadge({required this.title, required this.imageUrl});
  final String title, imageUrl;
}

final class TwitchChatMetadata {
  TwitchChatMetadata({
    required Map<String, TwitchPublicProfile> users,
    required Map<String, TwitchPublicBadge> badges,
  }) : users = Map.unmodifiable(users),
       badges = Map.unmodifiable(badges);
  final Map<String, TwitchPublicProfile> users;

  /// Global: /set/version. Channel: channel/set/version.
  final Map<String, TwitchPublicBadge> badges;
}

/// On-demand public metadata only. Never returns email, tokens or full users
/// payloads even when the authenticated user granted user:read:email.
final class TwitchChatMetadataSource {
  TwitchChatMetadataSource({required this.dataService, this.request});
  final ShowRunnerDataService dataService;
  final TwitchRequest? request;
  final _scope = ProviderOperationScope();

  Future<TwitchChatMetadata> load(
    Set<String> users,
    Set<String> channels,
  ) async {
    _scope.requireOpen();
    if (users.isEmpty ||
        users.length > 100 ||
        channels.length > 10 ||
        [...users, ...channels].any((id) => id.isEmpty || id.length > 128)) {
      throw ArgumentError(
        'Profile batches require 1–100 users and at most 10 channels.',
      );
    }
    var send = request;
    if (send == null) {
      final settings = await loadTwitchChannelSettings(dataService);
      _scope.requireOpen();
      final token = settings['accessToken'] as String? ?? '';
      final clientId = settings['clientId'] as String? ?? '';
      if (token.isEmpty || clientId.isEmpty) {
        throw StateError('Connect Twitch to load public profiles.');
      }
      send = createTwitchRuntimeRequest(
        accessToken: token,
        clientId: clientId,
        scope: _scope,
      );
    }
    final rows = _rows(
      await send('GET', '/helix/users', {'id': users.toList()}, {}),
    );
    final profiles = <String, TwitchPublicProfile>{};
    for (final row in rows) {
      final id = row['id'];
      if (id is! String || !users.contains(id)) continue;
      profiles[id] = TwitchPublicProfile(
        id: id,
        name: _label(row['display_name']),
        login: _label(row['login']),
        avatarUrl: twitchProfileImage(row['profile_image_url']),
      );
    }
    final badges = <String, TwitchPublicBadge>{};
    for (final channel in ['', ...channels]) {
      _scope.requireOpen();
      final rows = _rows(
        await send(
          'GET',
          channel.isEmpty ? '/helix/chat/badges/global' : '/helix/chat/badges',
          {if (channel.isNotEmpty) 'broadcaster_id': channel},
          {},
        ),
      );
      for (final row in rows) {
        final setId = row['set_id'];
        final versions = row['versions'];
        if (setId is! String || versions is! List) continue;
        for (final version in versions.whereType<Map>()) {
          if (badges.length >= 4096) {
            throw StateError('Twitch badge catalog exceeds its budget.');
          }
          final id = version['id'];
          final url = twitchProfileImage(version['image_url_1x']);
          if (id is String && url != null) {
            badges['$channel/$setId/$id'] = TwitchPublicBadge(
              title: _label(version['title']),
              imageUrl: url,
            );
          }
        }
      }
    }
    _scope.requireOpen();
    return TwitchChatMetadata(users: profiles, badges: badges);
  }

  List<Map> _rows(RuntimeMap response) {
    final data = response['data'];
    if (data is! List || data.length > 4096 || data.any((row) => row is! Map)) {
      throw StateError('Invalid public Twitch metadata.');
    }
    return data.cast<Map>();
  }

  String _label(Object? value) =>
      value is String && value.length <= 256 ? value : '';
  Future<void> close() => _scope.close();
}
