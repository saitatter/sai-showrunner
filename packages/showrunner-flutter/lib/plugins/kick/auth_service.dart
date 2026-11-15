import 'dart:io';

import '../../services/http_provider_transports.dart';
import '../../services/oauth_token.dart';
import '../../services/showrunner_data_service.dart';
import '../runtime/provider_operation_policy.dart';
import 'api_client.dart';
import 'contracts.dart';

const kickOAuthRedirectUrl = 'http://localhost:53543/oauth/callback';
const kickOAuthScopes = <String>[
  'user:read',
  'chat:write',
  'events:subscribe',
  'moderation:ban',
  'moderation:chat_message:manage',
];

/// A single browser connection attempt, cancelled with its workspace owner.
final class KickAuthService {
  KickAuthService({required this.dataService, this.openAuthorizationUrl});
  final ShowRunnerDataService dataService;
  final Future<void> Function(Uri)? openAuthorizationUrl;
  final _scope = ProviderOperationScope();
  final _clients = <HttpClient>[];
  HttpServer? _callback;
  bool _started = false;

  Future<void> connect() async {
    _scope.requireOpen();
    if (_started) throw StateError('Kick authorization is already started.');
    _started = true;
    final settings = await dataService.loadPluginSettings('kick');
    _scope.requireOpen();
    final clientId = settings['clientId'];
    final secret = settings['clientSecret'];
    if (clientId is! String ||
        clientId.trim().isEmpty ||
        secret is! String ||
        secret.isEmpty) {
      throw StateError(
        'Save a Kick client ID and client secret before connecting.',
      );
    }
    try {
      final flow = OAuthAuthorizationFlow(
        httpServerFactory: () async {
          final server = await HttpServer.bind(
            InternetAddress.loopbackIPv4,
            53543,
          );
          if (_scope.isClosed) {
            await server.close(force: true);
            throw StateError('Kick authorization was cancelled.');
          }
          _callback = server;
          return server;
        },
      );
      final tokens = await flow
          .authorize(
            requestBuilder: (redirect) {
              final verifier = createOAuthCodeVerifier();
              final state = createOAuthState();
              return OAuthAuthorizationRequest(
                state: state,
                codeVerifier: verifier,
                authorizationUrl: Uri.https('id.kick.com', '/oauth/authorize', {
                  'client_id': clientId,
                  'redirect_uri': redirect.toString(),
                  'response_type': 'code',
                  'scope': kickOAuthScopes.join(' '),
                  'state': state,
                  'code_challenge': createOAuthCodeChallenge(verifier),
                  'code_challenge_method': 'S256',
                }),
              );
            },
            openAuthorizationUrl: (url) async {
              _scope.requireOpen();
              await (openAuthorizationUrl ?? openOAuthUrlInBrowser)(url);
              _scope.requireOpen();
            },
            tokenClient: OAuthTokenClient(
              httpClientFactory: () {
                _scope.requireOpen();
                final client = HttpClient()
                  ..connectionTimeout = const Duration(seconds: 20);
                _clients.add(client);
                return client;
              },
            ),
            tokenEndpoint: kickTokenEndpoint,
            clientId: clientId,
            clientSecret: secret,
            callbackHost: 'localhost',
          )
          .timeout(const Duration(minutes: 5));
      _scope.requireOpen();
      final profile = await JsonHttpTransport(
        baseUrl: 'https://api.kick.com',
        operationScope: _scope,
        accessToken: tokens.accessToken,
      ).request('GET', '/public/v1/users', const {}, null);
      final data = profile['data'];
      if (data is! List || data.length != 1 || data.single is! Map) {
        throw const FormatException('Kick did not return the connected user.');
      }
      final user = data.single as Map;
      final userId = kickUserId(user['user_id'], 'userId').toString();
      final name = user['name'];
      if (name is! String || name.isEmpty || name.length > 256) {
        throw const FormatException('Kick did not return a user name.');
      }
      await dataService.transformPluginSettings('kick', (current) {
        _scope.requireOpen();
        if (!sameKickGrant(settings, current)) {
          throw StateError('Kick settings changed during authorization.');
        }
        return {
          ...current,
          'accessToken': tokens.accessToken,
          'refreshToken': tokens.refreshToken,
          'expiresAt': tokens.expiresAt?.toUtc().toIso8601String(),
          'userId': userId,
          'broadcasterId': userId,
          'userName': name,
        };
      });
    } catch (_) {
      if (_scope.isClosed) {
        throw StateError('Kick authorization was cancelled.');
      }
      rethrow;
    } finally {
      await close();
    }
  }

  Future<void> close() async {
    await _scope.close();
    await _callback?.close(force: true);
    _callback = null;
    for (final client in _clients) {
      client.close(force: true);
    }
    _clients.clear();
  }
}
