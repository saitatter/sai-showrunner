import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

final class OAuthTokenSet {
  const OAuthTokenSet({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
  });

  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;

  bool get isExpired =>
      accessToken.isEmpty ||
      (expiresAt != null && DateTime.now().isAfter(expiresAt!));
}

final class OAuthAuthorizationRequest {
  const OAuthAuthorizationRequest({
    required this.authorizationUrl,
    required this.state,
  });

  final Uri authorizationUrl;
  final String state;
}

final class OAuthAuthorizationClient {
  const OAuthAuthorizationClient();

  OAuthAuthorizationRequest buildRequest({
    required String authorizationEndpoint,
    required String clientId,
    required String redirectUri,
    required String state,
    required List<String> scopes,
  }) {
    return OAuthAuthorizationRequest(
      state: state,
      authorizationUrl: Uri.parse(authorizationEndpoint).replace(
        queryParameters: {
          'client_id': clientId,
          'redirect_uri': redirectUri,
          'response_type': 'code',
          'scope': scopes.join(' '),
          'state': state,
          'access_type': 'offline',
          'prompt': 'consent',
        },
      ),
    );
  }
}

String createOAuthState([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = List<int>.generate(32, (_) => source.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

final class OAuthCallbackResult {
  const OAuthCallbackResult({required this.code, required this.state});

  final String code;
  final String state;
}

final class OAuthAuthorizationFlow {
  const OAuthAuthorizationFlow({this.httpServerFactory = _bindLoopback});

  final Future<HttpServer> Function() httpServerFactory;

  Future<OAuthTokenSet> authorize({
    required OAuthAuthorizationRequest Function(Uri redirectUri) requestBuilder,
    required Future<void> Function(Uri authorizationUrl) openAuthorizationUrl,
    required OAuthTokenClient tokenClient,
    required String tokenEndpoint,
    required String clientId,
    required String clientSecret,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final server = await httpServerFactory();
    final redirectUri = Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.host,
      port: server.port,
      path: '/oauth/callback',
    );
    final request = requestBuilder(redirectUri);
    try {
      final callback = _readCallback(server, request.state, timeout);
      await openAuthorizationUrl(request.authorizationUrl);
      final result = await callback;
      return tokenClient.exchangeCode(
        tokenEndpoint: tokenEndpoint,
        clientId: clientId,
        clientSecret: clientSecret,
        code: result.code,
        redirectUri: redirectUri.toString(),
      );
    } finally {
      await server.close(force: true);
    }
  }

  Future<OAuthCallbackResult> _readCallback(
    HttpServer server,
    String expectedState,
    Duration timeout,
  ) async {
    try {
      await for (final request in server.timeout(timeout)) {
        final query = request.uri.queryParameters;
        final response = request.response;
        response.headers.contentType = ContentType.html;
        if (query['error'] != null) {
          response.statusCode = HttpStatus.badRequest;
          response.write('Authorization failed. You can close this window.');
          await response.close();
          throw StateError('OAuth authorization failed: ${query['error']}');
        }
        if (query['state'] != expectedState) {
          response.statusCode = HttpStatus.badRequest;
          response.write(
            'Authorization state did not match. You can close this window.',
          );
          await response.close();
          throw StateError('OAuth authorization state did not match.');
        }
        final code = query['code'];
        if (code == null || code.isEmpty) {
          response.statusCode = HttpStatus.badRequest;
          response.write(
            'Authorization code was missing. You can close this window.',
          );
          await response.close();
          throw const FormatException(
            'OAuth callback did not contain an authorization code.',
          );
        }
        response.write('Authorization complete. You can close this window.');
        await response.close();
        return OAuthCallbackResult(code: code, state: expectedState);
      }
      throw TimeoutException('OAuth authorization timed out.', timeout);
    } on TimeoutException {
      rethrow;
    }
  }
}

final class OAuthTokenClient {
  const OAuthTokenClient({this.httpClientFactory = _defaultHttpClient});

  final HttpClient Function() httpClientFactory;
  static const maxAttempts = 3;

  Future<OAuthTokenSet> refresh({
    required String tokenEndpoint,
    required String clientId,
    required String clientSecret,
    required String refreshToken,
  }) async {
    late String body;
    late int statusCode;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final client = httpClientFactory();
      final request = await client.postUrl(Uri.parse(tokenEndpoint));
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      request.write(
        Uri(
          queryParameters: {
            'client_id': clientId,
            'client_secret': clientSecret,
            'refresh_token': refreshToken,
            'grant_type': 'refresh_token',
          },
        ).query,
      );
      final response = await request.close();
      body = await utf8.decoder.bind(response).join();
      statusCode = response.statusCode;
      client.close(force: true);
      if (statusCode >= 200 && statusCode < 300) break;
      if (attempt < maxAttempts && statusCode >= 500) {
        await Future<void>.delayed(
          Duration(milliseconds: 100 * (1 << (attempt - 1))),
        );
        continue;
      }
      throw HttpException('OAuth refresh failed ($statusCode): $body');
    }
    final token = _decodeTokenSet(body);
    return OAuthTokenSet(
      accessToken: token.accessToken,
      refreshToken: token.refreshToken ?? refreshToken,
      expiresAt: token.expiresAt,
    );
  }

  Future<OAuthTokenSet> exchangeCode({
    required String tokenEndpoint,
    required String clientId,
    required String clientSecret,
    required String code,
    required String redirectUri,
  }) async {
    late String body;
    late int statusCode;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final client = httpClientFactory();
      try {
        final request = await client.postUrl(Uri.parse(tokenEndpoint));
        request.headers.contentType = ContentType(
          'application',
          'x-www-form-urlencoded',
          charset: 'utf-8',
        );
        request.write(
          Uri(
            queryParameters: {
              'client_id': clientId,
              'client_secret': clientSecret,
              'code': code,
              'redirect_uri': redirectUri,
              'grant_type': 'authorization_code',
            },
          ).query,
        );
        final response = await request.close();
        body = await utf8.decoder.bind(response).join();
        statusCode = response.statusCode;
      } finally {
        client.close(force: true);
      }
      if (statusCode >= 200 && statusCode < 300) break;
      if (attempt < maxAttempts && statusCode >= 500) {
        await Future<void>.delayed(
          Duration(milliseconds: 100 * (1 << (attempt - 1))),
        );
        continue;
      }
      throw HttpException('OAuth code exchange failed ($statusCode): $body');
    }
    return _decodeTokenSet(body);
  }
}

final class OAuthTokenManager {
  OAuthTokenManager({required this.current, required this.refresh});

  OAuthTokenSet? current;
  final Future<OAuthTokenSet> Function(String refreshToken) refresh;
  Future<OAuthTokenSet?>? _refreshing;

  Future<String?> accessToken() async {
    final token = current;
    if (token == null || !token.isExpired || token.refreshToken == null) {
      return token?.accessToken;
    }
    _refreshing ??= refresh(token.refreshToken!);
    try {
      current = await _refreshing;
      return current?.accessToken;
    } finally {
      _refreshing = null;
    }
  }
}

HttpClient _defaultHttpClient() => HttpClient();

Future<HttpServer> _bindLoopback() =>
    HttpServer.bind(InternetAddress.loopbackIPv4, 0);

OAuthTokenSet _decodeTokenSet(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map || decoded['access_token'] is! String) {
    throw const FormatException(
      'OAuth response did not contain an access token.',
    );
  }
  final expiresIn = (decoded['expires_in'] as num?)?.toInt();
  return OAuthTokenSet(
    accessToken: decoded['access_token'] as String,
    refreshToken: decoded['refresh_token'] as String?,
    expiresAt: expiresIn == null
        ? null
        : DateTime.now().add(Duration(seconds: expiresIn)),
  );
}
