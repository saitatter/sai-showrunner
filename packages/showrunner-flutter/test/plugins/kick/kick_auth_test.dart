import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/secret_settings_store.dart';
import 'package:showrunner_flutter/plugins/kick/api_client.dart';
import 'package:showrunner_flutter/plugins/kick/auth_service.dart';
import 'package:showrunner_flutter/services/oauth_token.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  late Directory root;
  late ShowRunnerDataService data;
  late HttpServer api;
  late List<({String path, Map<String, String> form})> calls;
  Future<void> Function()? beforeRefresh;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('kick-auth-fixture-');
    data = ShowRunnerDataService(
      root,
      secretSettings: SecretSettingsStore(
        directory: Directory('${root.path}/secrets'),
        encrypt: (bytes) async => bytes,
        decrypt: (bytes) async => bytes,
      ),
    );
    calls = [];
    beforeRefresh = null;
    api = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    api.listen((request) async {
      try {
        final text = await utf8.decoder.bind(request).join();
        final form = request.uri.path == '/oauth/token'
            ? Uri.splitQueryString(text)
            : <String, String>{};
        calls.add((path: request.uri.path, form: form));
        if (form['grant_type'] == 'refresh_token') await beforeRefresh?.call();
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(
            request.uri.path == '/oauth/token'
                ? {
                    'access_token': 'fixture-fresh',
                    'refresh_token': 'fixture-refresh',
                    'expires_in': 3600,
                  }
                : {
                    'data': [
                      {
                        'user_id': 7,
                        'name': 'Fixture Owner',
                        'email': 'private@example.test',
                      },
                    ],
                  },
          ),
        );
        await request.response.close();
      } catch (_) {
        await request.response.close();
      }
    });
  });
  tearDown(() async {
    await api.close(force: true);
    await root.delete(recursive: true);
  });

  Future<T> routed<T>(Future<T> Function() run) =>
      HttpOverrides.runWithHttpOverrides(run, _RoutingOverrides(api.port));

  test(
    'Kick PKCE uses the exact localhost callback and persists only verified identity',
    () async {
      await data.savePluginSettings('kick', {
        'clientId': 'fixture-client',
        'clientSecret': 'fixture-secret',
        'publicWebhookUrl': 'https://example.test/kick/webhook',
      });
      await routed(() async {
        final auth = KickAuthService(
          dataService: data,
          openAuthorizationUrl: (url) async {
            expect(url.host, 'id.kick.com');
            expect(url.queryParameters['redirect_uri'], kickOAuthRedirectUrl);
            expect(url.queryParameters['code_challenge_method'], 'S256');
            expect(url.queryParameters.containsKey('client_secret'), isFalse);
            final browser = HttpClient();
            try {
              final request = await browser.getUrl(
                Uri.parse(kickOAuthRedirectUrl).replace(
                  queryParameters: {
                    'state': url.queryParameters['state']!,
                    'code': 'fixture-code',
                  },
                ),
              );
              await (await request.close()).drain<void>();
            } finally {
              browser.close(force: true);
            }
          },
        );
        addTearDown(auth.close);
        await auth.connect();
      });
      final exchange = calls
          .singleWhere((call) => call.path == '/oauth/token')
          .form;
      expect(exchange['redirect_uri'], kickOAuthRedirectUrl);
      expect(exchange['client_secret'], 'fixture-secret');
      expect(exchange['code_verifier']!.length, greaterThanOrEqualTo(43));
      final saved = await data.loadPluginSettings('kick');
      expect(saved['broadcasterId'], '7');
      expect(saved['userName'], 'Fixture Owner');
      expect(saved['publicWebhookUrl'], 'https://example.test/kick/webhook');
      expect(saved.containsKey('email'), isFalse);
    },
  );

  test('refresh is single-flight and preserves unrelated settings', () async {
    await data.savePluginSettings('kick', {
      'clientId': 'fixture-client',
      'clientSecret': 'fixture-secret',
      'accessToken': 'fixture-expired',
      'refreshToken': 'fixture-refresh',
      'broadcasterId': '7',
      'expiresAt': DateTime.utc(2020).toIso8601String(),
    });
    final refreshing = Completer<void>(), release = Completer<void>();
    beforeRefresh = () async {
      refreshing.complete();
      await release.future;
    };
    final client = KickApiClient(dataService: data);
    addTearDown(client.close);
    await routed(() async {
      final requests = Future.wait([
        client.request('GET', '/public/v1/users', const {}, null),
        client.request('GET', '/public/v1/users', const {}, null),
      ]);
      await refreshing.future;
      await data.updatePluginSetting(
        'kick',
        'publicWebhookUrl',
        'https://new.example.test/kick/webhook',
      );
      release.complete();
      await requests;
      await client.request('GET', '/public/v1/users', const {}, null);
    });
    expect(calls.where((call) => call.path == '/oauth/token'), hasLength(1));
    final saved = await data.loadPluginSettings('kick');
    expect(saved['accessToken'], 'fixture-fresh');
    expect(saved['publicWebhookUrl'], 'https://new.example.test/kick/webhook');
  });

  test('refresh cannot overwrite a replacement account', () async {
    await data.savePluginSettings('kick', {
      'clientId': 'fixture-client',
      'clientSecret': 'fixture-secret',
      'accessToken': 'fixture-expired',
      'refreshToken': 'fixture-refresh',
      'broadcasterId': '7',
      'expiresAt': DateTime.utc(2020).toIso8601String(),
    });
    final refreshing = Completer<void>(), release = Completer<void>();
    beforeRefresh = () async {
      refreshing.complete();
      await release.future;
    };
    final client = KickApiClient(dataService: data);
    addTearDown(client.close);
    await routed(() async {
      final request = expectLater(
        client.request('GET', '/public/v1/users', const {}, null),
        throwsStateError,
      );
      await refreshing.future;
      await data.updatePluginSettings('kick', {
        'accessToken': 'replacement',
        'broadcasterId': '99',
      });
      release.complete();
      await request;
    });
    expect(
      (await data.loadPluginSettings('kick'))['accessToken'],
      'replacement',
    );
    expect(calls.where((call) => call.path == '/public/v1/users'), isEmpty);
  });

  test(
    'closing sign-in prevents token exchange and late credential writes',
    () async {
      await data.savePluginSettings('kick', {
        'clientId': 'fixture-client',
        'clientSecret': 'fixture-secret',
      });
      final opened = Completer<void>(), release = Completer<void>();
      final auth = KickAuthService(
        dataService: data,
        openAuthorizationUrl: (_) async {
          opened.complete();
          await release.future;
        },
      );
      await routed(() async {
        final connecting = expectLater(auth.connect(), throwsStateError);
        await opened.future;
        await auth.close();
        release.complete();
        await connecting;
      });
      expect(calls, isEmpty);
      expect(
        (await data.loadPluginSettings('kick')).containsKey('accessToken'),
        isFalse,
      );
    },
  );

  test(
    'shared authorization rejects a non-loopback callback before binding',
    () async {
      var bound = false;
      final flow = OAuthAuthorizationFlow(
        httpServerFactory: () async {
          bound = true;
          return HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        },
      );
      await expectLater(
        flow.authorize(
          requestBuilder: (_) => throw StateError('unused'),
          openAuthorizationUrl: (_) async {},
          tokenClient: const OAuthTokenClient(),
          tokenEndpoint: 'https://id.kick.com/oauth/token',
          clientId: 'fixture',
          callbackHost: 'example.test',
        ),
        throwsArgumentError,
      );
      expect(bound, isFalse);
    },
  );
}

class _RoutingOverrides extends HttpOverrides {
  _RoutingOverrides(this.port);
  final int port;
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _RoutingClient(super.createHttpClient(context), port);
}

class _RoutingClient implements HttpClient {
  _RoutingClient(this.delegate, this.port);
  final HttpClient delegate;
  final int port;
  @override
  set connectionTimeout(Duration? value) => delegate.connectionTimeout = value;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    if (const {'api.kick.com', 'id.kick.com'}.contains(url.host)) {
      url = url.replace(scheme: 'http', host: '127.0.0.1', port: port);
    } else if (url.host != 'localhost' && url.host != '127.0.0.1') {
      throw StateError('Unexpected external test request.');
    }
    return delegate.openUrl(method, url);
  }

  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);
  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);
  @override
  void close({bool force = false}) => delegate.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
