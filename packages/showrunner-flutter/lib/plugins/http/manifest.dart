import 'dart:convert';
import 'dart:io';

import '../../components/data_inputs/data_input.dart';
import '../../runtime/expression.dart';
import '../registry/plugin_registry.dart';

const _requestSchema = DartDataInputSchema(
  label: 'HTTP request',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'URL',
      key: 'url',
      kind: DartDataInputKind.text,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Method',
      key: 'method',
      kind: DartDataInputKind.enumeration,
      options: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'],
      required: true,
      defaultValue: 'GET',
    ),
    DartDataInputSchema(
      label: 'Content type',
      key: 'contentType',
      kind: DartDataInputKind.text,
    ),
    DartDataInputSchema(
      label: 'Headers (JSON)',
      key: 'headers',
      kind: DartDataInputKind.multilineText,
    ),
    DartDataInputSchema(
      label: 'Body',
      key: 'body',
      kind: DartDataInputKind.multilineText,
    ),
  ],
);

DartPluginManifest createHttpPlugin() => const DartPluginManifest(
  id: 'http',
  name: 'HTTP',
  actions: [
    DartActionDefinition(
      pluginId: 'http',
      actionId: 'request',
      displayName: 'HTTP Request',
      invoke: _httpRequest,
      configSchema: _requestSchema,
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
