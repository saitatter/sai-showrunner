import 'dart:io';
import 'dart:convert';

import '../../services/oauth_token.dart';
import '../../persistence/resource_repository.dart';
import '../../services/showrunner_data_service.dart';
import '../../schema/automation.dart';
import '../../schema/resource.dart';

typedef TwitchAccountAuthorizer =
    Future<OAuthTokenSet> Function({
      required String clientId,
      required String clientSecret,
      required List<String> scopes,
    });

typedef TwitchIdentityLoader =
    Future<JsonMap> Function(String accessToken, String clientId);

/// Signs in and persists one of the reference Twitch account resources.
///
/// The channel and bot accounts deliberately share the configured OAuth app,
/// but keep separate scopes, identities and credentials. This mirrors the
/// Electron account model while using the Flutter persistence boundary.
final class TwitchAccountAuthService {
  TwitchAccountAuthService({
    required this.dataService,
    this.authorize,
    this.loadIdentity,
    this.openAuthorizationUrl,
  });

  final ShowRunnerDataService dataService;
  final TwitchAccountAuthorizer? authorize;
  final TwitchIdentityLoader? loadIdentity;
  final Future<void> Function(Uri url)? openAuthorizationUrl;

  Future<ResourceData> authorizeAccount(String accountId) async {
    final normalizedId = _accountId(accountId);
    final settings = await dataService.loadPluginSettings('twitch');
    final clientId = settings['clientId']?.toString().trim() ?? '';
    final clientSecret = settings['clientSecret']?.toString().trim() ?? '';
    if (clientId.isEmpty || clientSecret.isEmpty) {
      throw StateError(
        'Twitch client ID and client secret are required before account sign-in.',
      );
    }
    final scopes = normalizedId == 'bot' ? _botScopes : _channelScopes;
    final token = authorize == null
        ? await _authorizeWithBrowser(
            clientId: clientId,
            clientSecret: clientSecret,
            scopes: scopes,
          )
        : await authorize!(
            clientId: clientId,
            clientSecret: clientSecret,
            scopes: scopes,
          );
    if (token.accessToken.trim().isEmpty) {
      throw StateError('Twitch authorization did not return an access token.');
    }
    final identity = loadIdentity == null
        ? await _loadTwitchIdentity(token.accessToken, clientId)
        : await loadIdentity!(token.accessToken, clientId);
    final account = await _repository.load(normalizedId);
    final config = <String, dynamic>{
      ...account?.config ?? <String, dynamic>{},
      'name': identity['displayName']?.toString().trim().isNotEmpty == true
          ? identity['displayName']
          : account?.config['name'] ?? normalizedId,
      'twitchId': identity['id']?.toString() ?? '',
      'email': identity['email']?.toString() ?? account?.config['email'] ?? '',
      if (identity['broadcasterType']?.toString() == 'affiliate' ||
          identity['broadcasterType']?.toString() == 'partner')
        'isAffiliate': true,
      if (identity['broadcasterType']?.toString() == 'partner')
        'isPartner': true,
      'accessToken': token.accessToken,
      if (token.refreshToken != null) 'refreshToken': token.refreshToken,
      if (token.expiresAt != null)
        'expiresAt': token.expiresAt!.toIso8601String(),
    };
    final updated = ResourceData(
      id: normalizedId,
      config: config,
      state: {...?account?.state, 'authenticated': true},
    );
    await _repository.save(updated);
    return updated;
  }

  Future<ResourceData?> loadAccount(String accountId) =>
      _repository.load(_accountId(accountId));

  ResourceRepository get _repository => ResourceRepository(
    Directory('${dataService.userDirectory.path}/accounts/twitch'),
    resourceType: 'TwitchAccount',
    secretSettings: dataService.secretSettingsStore,
  );

  Future<OAuthTokenSet> _authorizeWithBrowser({
    required String clientId,
    required String clientSecret,
    required List<String> scopes,
  }) => OAuthAuthorizationFlow().authorize(
    requestBuilder: (redirectUri) {
      final state = createOAuthState();
      return const OAuthAuthorizationClient().buildRequest(
        authorizationEndpoint: 'https://id.twitch.tv/oauth2/authorize',
        clientId: clientId,
        redirectUri: redirectUri.toString(),
        state: state,
        scopes: scopes,
      );
    },
    openAuthorizationUrl: openAuthorizationUrl ?? _openAuthorizationUrl,
    tokenClient: const OAuthTokenClient(),
    tokenEndpoint: 'https://id.twitch.tv/oauth2/token',
    clientId: clientId,
    clientSecret: clientSecret,
  );
}

const _channelScopes = <String>[
  'user:read:email',
  'channel:manage:broadcast',
  'channel:read:redemptions',
  'channel:manage:redemptions',
  'moderator:read:followers',
  'moderator:manage:shoutouts',
  'moderator:manage:banned_users',
  'channel:manage:raids',
  'channel:manage:polls',
  'channel:manage:predictions',
  'channel:read:subscriptions',
  'channel:read:hype_train',
  'channel:read:ads',
  'channel:manage:ads',
  'clips:edit',
];

const _botScopes = <String>[
  'user:read:email',
  'chat:read',
  'chat:edit',
  'moderator:manage:announcements',
];

String _accountId(String value) {
  final normalized = value.trim();
  if (normalized != 'channel' && normalized != 'bot') {
    throw ArgumentError.value(value, 'accountId', 'Expected channel or bot.');
  }
  return normalized;
}

Future<JsonMap> _loadTwitchIdentity(String accessToken, String clientId) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse('https://api.twitch.tv/helix/users'),
    );
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $accessToken')
      ..set('Client-Id', clientId);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Twitch identity request failed (${response.statusCode}): $body',
      );
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map ||
        decoded['data'] is! List ||
        decoded['data'].isEmpty) {
      throw const FormatException('Twitch identity response was empty.');
    }
    final first = decoded['data'].first;
    if (first is! Map) {
      throw const FormatException('Twitch identity response was invalid.');
    }
    return Map<String, dynamic>.from(first);
  } finally {
    client.close(force: true);
  }
}

Future<void> _openAuthorizationUrl(Uri url) async {
  if (!Platform.isWindows) {
    throw UnsupportedError(
      'Twitch account authorization is supported on Windows only.',
    );
  }
  await Process.start('cmd.exe', ['/c', 'start', '', url.toString()]);
}

/// Resolves the account resources used by the reference Twitch plugin.
///
/// Older Flutter profiles stored these values in `settings/twitch.yaml`, so
/// the settings map remains the fallback. Account resources win when present,
/// which makes imported `channel` and `bot` accounts operational without a
/// second manual configuration step.
Future<JsonMap> loadTwitchChannelSettings(
  ShowRunnerDataService dataService,
) async {
  final settings = await dataService.loadPluginSettings('twitch');
  final repository = ResourceRepository(
    Directory('${dataService.userDirectory.path}/accounts/twitch'),
    resourceType: 'TwitchAccount',
    secretSettings: dataService.secretSettingsStore,
  );
  final channel = await repository.load('channel');
  final bot = await repository.load('bot');
  if (channel == null && bot == null) return settings;

  final resolved = <String, dynamic>{...settings};
  if (channel != null) {
    _copyIfPresent(resolved, 'accessToken', channel.config['accessToken']);
    _copyIfPresent(resolved, 'refreshToken', channel.config['refreshToken']);
    _copyIfPresent(resolved, 'broadcasterId', channel.config['twitchId']);
  }
  if (bot != null) {
    _copyIfPresent(resolved, 'moderatorId', bot.config['twitchId']);
  }
  return resolved;
}

void _copyIfPresent(Map<String, dynamic> target, String key, Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isNotEmpty) target[key] = text;
}
