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
  });
}
