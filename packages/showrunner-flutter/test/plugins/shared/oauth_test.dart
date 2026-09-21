import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/services/oauth_token.dart';
import 'package:showrunner_flutter/services/provider_settings_validator.dart';

void main() {
  test('deduplicates concurrent OAuth refreshes', () async {
    var refreshes = 0;
    final manager = OAuthTokenManager(
      current: OAuthTokenSet(
        accessToken: 'expired',
        refreshToken: 'refresh',
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      ),
      refresh: (token) async {
        refreshes++;
        await Future<void>.delayed(Duration.zero);
        return const OAuthTokenSet(
          accessToken: 'fresh',
          refreshToken: 'refresh',
        );
      },
    );

    final tokens = await Future.wait([
      manager.accessToken(),
      manager.accessToken(),
    ]);

    expect(tokens, ['fresh', 'fresh']);
    expect(refreshes, 1);
  });

  test('builds an authorization request for an expired OAuth set', () {
    expect(
      const OAuthTokenSet(accessToken: '', refreshToken: 'refresh').isExpired,
      isTrue,
    );
    final request = const OAuthAuthorizationClient().buildRequest(
      authorizationEndpoint: 'https://accounts.example.test/authorize',
      clientId: 'client-id',
      redirectUri: 'http://127.0.0.1:4455/callback',
      state: 'state-1',
      scopes: ['chat.read', 'chat.write'],
    );
    expect(request.state, 'state-1');
    expect(request.authorizationUrl.queryParameters['client_id'], 'client-id');
    expect(
      request.authorizationUrl.queryParameters['scope'],
      'chat.read chat.write',
    );
  });

  test('adds a PKCE challenge and keeps the verifier out of the URL', () {
    final verifier = createOAuthCodeVerifier(Random(7));
    final request = const OAuthAuthorizationClient().buildRequest(
      authorizationEndpoint: 'https://accounts.example.test/authorize',
      clientId: 'client-id',
      redirectUri: 'http://127.0.0.1:4455/oauth/callback',
      state: 'state-1',
      scopes: ['youtube.readonly'],
      codeVerifier: verifier,
    );

    expect(
      request.authorizationUrl.queryParameters['code_challenge'],
      createOAuthCodeChallenge(verifier),
    );
    expect(
      request.authorizationUrl.queryParameters['code_challenge_method'],
      'S256',
    );
    expect(
      request.authorizationUrl.queryParameters.containsKey('code_verifier'),
      isFalse,
    );
  });

  test('completes the Twitch-style browser fragment flow', () async {
    final flow = const OAuthImplicitAuthorizationFlow();
    final token = await flow.authorize(
      authorizationEndpoint: 'https://id.twitch.tv/oauth2/authorize',
      clientId: 'public-client',
      scopes: const ['chat:read'],
      openAuthorizationUrl: (url) async {
        expect(url.queryParameters['response_type'], 'token');
        expect(url.queryParameters['client_id'], 'public-client');
        expect(url.queryParameters.containsKey('client_secret'), isFalse);
        final redirect = Uri.parse(url.queryParameters['redirect_uri']!);
        final client = HttpClient();
        try {
          final page = await client.getUrl(redirect);
          await page.close();
          final callback = redirect.replace(
            queryParameters: {
              'access_token': 'browser-token',
              'state': url.queryParameters['state']!,
              'expires_in': '3600',
            },
          );
          final response = await client.getUrl(callback);
          await response.close();
        } finally {
          client.close(force: true);
        }
      },
    );

    expect(token.accessToken, 'browser-token');
    expect(token.refreshToken, isNull);
    expect(token.expiresAt, isNotNull);
  });

  test('validates provider settings before transport startup', () {
    expect(
      validateProviderSettings('obs', {
        'host': '127.0.0.1',
        'port': 4455,
      }).isValid,
      isTrue,
    );
    expect(
      validateProviderSettings('obs', {'host': '', 'port': 0}).errors,
      hasLength(2),
    );
    expect(
      validateProviderSettings('twitch', {
        'clientId': 'client',
        'accessToken': 'token',
        'broadcasterId': 'broadcaster',
        'moderatorId': 'moderator',
      }).isValid,
      isTrue,
    );
    expect(validateProviderSettings('youtube', {}).isValid, isFalse);
    expect(
      validateProviderSettings('youtube', {
        'clientId': 'desktop-client',
        'accessToken': 'token',
      }).isValid,
      isTrue,
    );
  });
}
