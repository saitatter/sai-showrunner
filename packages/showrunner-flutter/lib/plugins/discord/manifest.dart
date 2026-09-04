import 'dart:convert';
import 'dart:io';

import '../../components/data_inputs/data_input.dart';
import '../../runtime/expression.dart';
import '../registry/plugin_registry.dart';

typedef DiscordRequest =
    Future<RuntimeMap> Function(String url, RuntimeMap body);

final class DiscordTransport {
  const DiscordTransport(this.request);

  final DiscordRequest request;
}

final class DiscordHttpTransport {
  const DiscordHttpTransport();

  Future<RuntimeMap> request(String url, RuntimeMap body) async {
    final uri = Uri.parse(url);
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      throw ArgumentError('Discord webhook URL must use HTTP or HTTPS.');
    }
    final client = HttpClient();
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response = await request.close();
      final responseBody = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Discord webhook failed (${response.statusCode}): $responseBody',
        );
      }
      return {
        'statusCode': response.statusCode,
        if (responseBody.isNotEmpty) 'body': responseBody,
      };
    } finally {
      client.close(force: true);
    }
  }
}

const _messageSchema = DartDataInputSchema(
  label: 'Discord message',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Webhook',
      key: 'webhook',
      kind: DartDataInputKind.resource,
      resourceType: 'DiscordWebhook',
      required: true,
    ),
    DartDataInputSchema(
      label: 'Message',
      key: 'message',
      kind: DartDataInputKind.multilineText,
      required: true,
    ),
  ],
);

DartPluginManifest createDiscordPlugin({DiscordTransport? transport}) =>
    DartPluginManifest(
      id: 'discord',
      name: 'Discord',
      actions: [
        DartActionDefinition(
          pluginId: 'discord',
          actionId: 'discordMessage',
          displayName: 'Discord Message',
          configSchema: _messageSchema,
          invoke: (config, context) => _sendDiscordMessage(
            transport ?? DiscordTransport(DiscordHttpTransport().request),
            config,
          ),
        ),
      ],
    );

Future<Object?> _sendDiscordMessage(
  DiscordTransport transport,
  RuntimeMap config,
) async {
  final message = config['message']?.toString() ?? '';
  final webhook = config['webhook'];
  final url = webhook is Map
      ? webhook['webhookUrl']?.toString().trim()
      : config['webhookUrl']?.toString().trim();
  if (url == null || url.isEmpty) {
    return {'sent': false, 'reason': 'Webhook unconfigured'};
  }
  if (message.trim().isEmpty) {
    return {'sent': false, 'reason': 'Message is empty'};
  }
  final response = await transport.request(url, {
    'content': message,
    if (config['username'] != null) 'username': config['username'],
    if (config['avatarUrl'] != null) 'avatar_url': config['avatarUrl'],
    if (config['tts'] != null) 'tts': config['tts'] == true,
  });
  return {
    'sent': true,
    'message': message,
    if (response['statusCode'] != null) 'statusCode': response['statusCode'],
  };
}
