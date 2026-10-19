import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/youtube/auth_service.dart';
import 'package:showrunner_flutter/persistence/secret_settings_store.dart';
import 'package:showrunner_flutter/services/oauth_token.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  test('connects YouTube through browser OAuth with PKCE', () async {
    final root = await Directory.systemTemp.createTemp('showrunner-youtube-');
    addTearDown(() => root.delete(recursive: true));
    Future<List<int>> cipher(List<int> bytes) async =>
        bytes.map((byte) => byte ^ 0x5a).toList();
    final dataService = ShowRunnerDataService(
      root,
      secretSettings: SecretSettingsStore(
        directory: Directory('${root.path}/secrets'),
        encrypt: cipher,
        decrypt: cipher,
      ),
    );
    await dataService.savePluginSettings('youtube', {
      'clientId': 'desktop-client',
      'clientSecret': 'desktop-secret',
    });

    final tokenServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => tokenServer.close(force: true));
    String? tokenBody;
    tokenServer.listen((request) async {
      tokenBody = await utf8.decoder.bind(request).join();
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'access_token': 'youtube-access',
            'refresh_token': 'youtube-refresh',
            'expires_in': 3600,
          }),
        );
      await request.response.close();
    });

    final service = YouTubeAuthService(
      dataService: dataService,
      tokenEndpoint: 'http://127.0.0.1:${tokenServer.port}/token',
      authorizationEndpoint: 'https://accounts.example.test/authorize',
      openAuthorizationUrl: (url) async {
        expect(url.queryParameters['response_type'], 'code');
        expect(url.queryParameters['code_challenge_method'], 'S256');
        final redirect = Uri.parse(url.queryParameters['redirect_uri']!);
        final callback = redirect.replace(
          queryParameters: {
            'code': 'authorization-code',
            'state': url.queryParameters['state']!,
          },
        );
        final client = HttpClient();
        try {
          final response = await client.getUrl(callback);
          await response.close();
        } finally {
          client.close(force: true);
        }
      },
      loadProfile: (token) async {
        expect(token, 'youtube-access');
        return const YouTubeProfile(
          channelId: 'channel-id',
          title: 'Test channel',
        );
      },
    );

    final connected = await service.connect();

    expect(connected['channelId'], 'channel-id');
    expect(connected['channelName'], 'Test channel');
    expect(connected['accessToken'], 'youtube-access');
    final tokenParameters = Uri.splitQueryString(tokenBody!);
    expect(tokenParameters['client_id'], 'desktop-client');
    expect(tokenParameters['client_secret'], 'desktop-secret');
    expect(tokenParameters['code'], 'authorization-code');
    expect(tokenParameters['code_verifier'], isNotEmpty);
    expect(
      createOAuthCodeChallenge(tokenParameters['code_verifier']!),
      isNotEmpty,
    );

    final saved = await dataService.loadPluginSettings('youtube');
    expect(saved['refreshToken'], 'youtube-refresh');
    expect(saved['channelName'], 'Test channel');
  });
}
