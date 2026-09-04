import 'dart:convert';
import 'dart:io';

import '../../runtime/expression.dart';
import '../registry/plugin_registry.dart';

DartPluginManifest createHttpPlugin() => const DartPluginManifest(
  id: 'http',
  name: 'HTTP',
  actions: [
    DartActionDefinition(
      pluginId: 'http',
      actionId: 'request',
      displayName: 'HTTP Request',
      invoke: _httpRequest,
    ),
  ],
);

Future<Object?> _httpRequest(
  RuntimeMap config,
  EvaluationContext context,
) async {
  final urlStr = config['url']?.toString() ?? '';
  if (urlStr.isEmpty) {
    throw ArgumentError('HTTP request URL is required.');
  }
  final uri = Uri.parse(urlStr);
  final method = (config['method']?.toString() ?? 'GET').toUpperCase();
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, uri);
    final contentType = config['contentType']?.toString();
    if (contentType != null && contentType.isNotEmpty) {
      request.headers.contentType = ContentType.parse(contentType);
    }
    final rawHeaders = config['headers']?.toString();
    if (rawHeaders != null && rawHeaders.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawHeaders);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            request.headers.add(entry.key.toString(), entry.value.toString());
          }
        }
      } on FormatException {
        // Ignore invalid headers json
      }
    }
    final body = config['body']?.toString();
    if (body != null && body.isNotEmpty) {
      request.write(body);
    }
    final response = await request.close();
    final responseBody = await utf8.decoder.bind(response).join();
    return {'statusCode': response.statusCode, 'body': responseBody};
  } finally {
    client.close();
  }
}
