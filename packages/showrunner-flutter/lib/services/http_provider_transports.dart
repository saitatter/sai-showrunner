import 'dart:convert';
import 'dart:io';

import '../runtime/expression.dart';

final class JsonHttpTransport {
  const JsonHttpTransport({
    required this.baseUrl,
    this.accessToken,
    this.accessTokenProvider,
    this.headers = const <String, String>{},
  });

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
    final uri = Uri.parse(baseUrl)
        .resolve(path)
        .replace(
          queryParameters: {
            ...query.map((key, value) => MapEntry(key, '$value')),
          },
        );
    final request = await HttpClient().openUrl(method, uri);
    request.headers.contentType = ContentType.json;
    headers.forEach(request.headers.set);
    final token = accessTokenProvider == null
        ? accessToken
        : await accessTokenProvider!();
    if (token?.isNotEmpty == true) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    if (body != null) request.write(jsonEncode(body));
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    dynamic decoded;
    if (text.isNotEmpty) decoded = jsonDecode(text);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Provider request failed (${response.statusCode}): $text',
      );
    }
    return decoded;
  }
}
