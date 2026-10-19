import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../runtime/expression.dart';
import 'http_policy.dart';

final class JsonHttpTransport {
  const JsonHttpTransport({
    required this.baseUrl,
    this.accessToken,
    this.accessTokenProvider,
    this.headers = const <String, String>{},
    this.timeout = const Duration(seconds: 20),
    this.maxResponseBytes = 4 * 1024 * 1024,
    this.client,
    this.maxRetries = 1,
  });

  final Duration timeout;
  final int maxResponseBytes;
  final HttpClient? client;
  final int maxRetries;
  final String baseUrl;
  final String? accessToken;
  final Future<String?> Function()? accessTokenProvider;
  final Map<String, String> headers;

  Future<RuntimeMap> request(
    String method,
    String path,
    RuntimeMap query,
    dynamic body,
  ) async {
    final decoded = await requestValue(method, path, query, body);
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
  }

  Future<dynamic> requestValue(
    String method,
    String path,
    RuntimeMap query,
    dynamic body,
  ) async {
    final safe = {'GET', 'HEAD'}.contains(method.toUpperCase());
    for (var attempt = 0; ; attempt++) {
      try {
        return await _requestValue(method, path, query, body);
      } on ProviderRateLimitException catch (error) {
        if (!safe || attempt >= maxRetries) rethrow;
        await Future<void>.delayed(error.delay);
      }
    }
  }

  Future<dynamic> _requestValue(
    String method,
    String path,
    RuntimeMap query,
    dynamic body,
  ) async {
    final uri = Uri.parse(baseUrl)
        .resolve(path)
        .replace(
          queryParameters: {
            ...query.map((key, value) => MapEntry(key, '$value')),
          },
        );
    final httpClient = client ?? (HttpClient()..connectionTimeout = timeout);
    HttpClientRequest? activeRequest;
    try {
      final request = await httpClient.openUrl(method, uri).timeout(timeout);
      activeRequest = request;
      request.headers.contentType = ContentType.json;
      headers.forEach(request.headers.set);
      final token = accessTokenProvider == null
          ? accessToken
          : await accessTokenProvider!().timeout(timeout);
      if (token?.isNotEmpty == true) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (body != null && !{'GET', 'HEAD'}.contains(method.toUpperCase())) {
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(timeout);
      final text = await readHttpText(
        response,
        maxBytes: maxResponseBytes,
      ).timeout(timeout);
      if (response.statusCode == 429) {
        throw ProviderRateLimitException(
          retryAfter: response.headers.value('retry-after'),
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Provider request failed (${response.statusCode}).',
        );
      }
      dynamic decoded;
      if (text.isNotEmpty) decoded = jsonDecode(text);
      return decoded;
    } on Object {
      activeRequest?.abort();
      rethrow;
    } finally {
      if (client == null) httpClient.close(force: true);
    }
  }
}
