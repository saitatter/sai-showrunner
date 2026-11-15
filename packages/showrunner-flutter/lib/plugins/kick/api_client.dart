import 'dart:io';

import '../../runtime/expression.dart';
import '../../services/http_provider_transports.dart';
import '../../services/oauth_token.dart';
import '../../services/showrunner_data_service.dart';
import '../runtime/provider_operation_policy.dart';

const kickTokenEndpoint = 'https://id.kick.com/oauth/token';

/// Reads current encrypted settings for every operation, including after a
/// connection made while the application is already running.
final class KickApiClient {
  KickApiClient({required this.dataService});

  final ShowRunnerDataService dataService;
  final scope = ProviderOperationScope();
  RuntimeMap? _grant;
  OAuthTokenManager? _manager;

  Future<Object?> readBroadcasterId() async {
    scope.requireOpen();
    final settings = await dataService.loadPluginSettings('kick');
    scope.requireOpen();
    return settings['broadcasterId'];
  }

  Future<RuntimeMap> request(
    String method,
    String path,
    RuntimeMap query,
    Object? body,
  ) async {
    scope.requireOpen();
    final settings = await dataService.loadPluginSettings('kick');
    scope.requireOpen();
    if (_grant == null || !sameKickGrant(_grant!, settings)) {
      _manager = _createManager(settings);
      _grant = Map.of(settings);
    }
    final manager = _manager;
    if (manager == null) throw StateError('Kick is not connected.');
    return JsonHttpTransport(
      baseUrl: 'https://api.kick.com',
      operationScope: scope,
      accessTokenProvider: () async {
        final token = await manager.accessToken();
        scope.requireOpen();
        final current = await dataService.loadPluginSettings('kick');
        scope.requireOpen();
        if (token == null ||
            token.isEmpty ||
            current['accessToken'] != token ||
            !const [
              'clientId',
              'clientSecret',
              'userId',
              'broadcasterId',
            ].every((field) => settings[field] == current[field])) {
          throw StateError(
            'Kick connection changed before the request was sent.',
          );
        }
        return token;
      },
    ).request(method, path, query, body);
  }

  Future<String> loadPublicKey() async {
    scope.requireOpen();
    final response = await JsonHttpTransport(
      baseUrl: 'https://api.kick.com',
      operationScope: scope,
      maxResponseBytes: 16384,
    ).request('GET', '/public/v1/public-key', const {}, null);
    final data = response['data'];
    final key = data is Map ? data['public_key'] : null;
    if (key is! String || key.isEmpty || key.length > 4096) {
      throw const FormatException('Kick did not return a public key.');
    }
    return key;
  }

  OAuthTokenManager? _createManager(RuntimeMap settings) {
    final clientId = settings['clientId'];
    final clientSecret = settings['clientSecret'];
    final accessToken = settings['accessToken'];
    final refreshToken = settings['refreshToken'];
    if (clientId is! String ||
        clientId.isEmpty ||
        clientSecret is! String ||
        clientSecret.isEmpty ||
        (accessToken is! String && refreshToken is! String)) {
      return null;
    }
    final rawExpiry = settings['expiresAt'];
    return OAuthTokenManager(
      current: OAuthTokenSet(
        accessToken: accessToken is String ? accessToken : '',
        refreshToken: refreshToken is String ? refreshToken : null,
        expiresAt: rawExpiry is String ? DateTime.tryParse(rawExpiry) : null,
      ),
      refresh: (token) async {
        final next = await refreshKickToken(
          scope: scope,
          clientId: clientId,
          clientSecret: clientSecret,
          refreshToken: token,
        );
        scope.requireOpen();
        RuntimeMap? persisted;
        await dataService.transformPluginSettings('kick', (current) {
          scope.requireOpen();
          if (!sameKickGrant(current, settings)) {
            throw StateError('Kick connection changed during token refresh.');
          }
          return persisted = {
            ...current,
            'accessToken': next.accessToken,
            'refreshToken': next.refreshToken ?? token,
            'expiresAt': next.expiresAt?.toUtc().toIso8601String(),
          };
        });
        scope.requireOpen();
        // Keep future refreshes bound to the grant we just persisted.
        settings = persisted!;
        _grant = Map.of(settings);
        return next;
      },
    );
  }

  Future<void> close() => scope.close();
}

bool sameKickGrant(RuntimeMap first, RuntimeMap second) => const [
  'clientId',
  'clientSecret',
  'accessToken',
  'refreshToken',
  'expiresAt',
  'userId',
  'broadcasterId',
].every((key) => first[key] == second[key]);

Future<OAuthTokenSet> refreshKickToken({
  required ProviderOperationScope scope,
  required String clientId,
  required String clientSecret,
  required String refreshToken,
}) async {
  final clients = <HttpClient>[];
  final releases = <void Function()>[];
  try {
    scope.requireOpen();
    return await OAuthTokenClient(
          httpClientFactory: () {
            scope.requireOpen();
            final client = HttpClient()
              ..connectionTimeout = const Duration(seconds: 20);
            clients.add(client);
            releases.add(scope.track(() => client.close(force: true)));
            return client;
          },
        )
        .refresh(
          tokenEndpoint: kickTokenEndpoint,
          clientId: clientId,
          clientSecret: clientSecret,
          refreshToken: refreshToken,
        )
        .timeout(const Duration(seconds: 20));
  } catch (_) {
    throw StateError('Kick token refresh failed. Reconnect the account.');
  } finally {
    for (final release in releases) {
      release();
    }
    for (final client in clients) {
      client.close(force: true);
    }
  }
}
