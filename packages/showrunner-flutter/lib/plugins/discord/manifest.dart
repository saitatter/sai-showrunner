import 'dart:convert';
import 'dart:io';

import '../../schema/data_input.dart';
import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';

typedef DiscordRequest =
    Future<RuntimeMap> Function(String url, RuntimeMap body);
typedef DiscordFileRequest =
    Future<RuntimeMap> Function(
      String url,
      RuntimeMap body,
      List<String> files,
    );

final class DiscordTransport {
  const DiscordTransport(this.request, {this.requestWithFiles});

  final DiscordRequest request;
  final DiscordFileRequest? requestWithFiles;
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
      return _readDiscordResponse(response);
    } finally {
      client.close(force: true);
    }
  }

  Future<RuntimeMap> requestWithFiles(
    String url,
    RuntimeMap body,
    List<String> files,
  ) async {
    final uri = Uri.parse(url);
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      throw ArgumentError('Discord webhook URL must use HTTP or HTTPS.');
    }

    final attachments = <({String name, List<int> bytes})>[];
    for (final path in files) {
      final file = File(path);
      if (!await file.exists()) {
        throw FileSystemException('Discord attachment does not exist.', path);
      }
      attachments.add((
        name: _attachmentName(path),
        bytes: await file.readAsBytes(),
      ));
    }

    final boundary =
        '----ShowRunnerDiscord${DateTime.now().microsecondsSinceEpoch}';
    final client = HttpClient();
    try {
      final request = await client.postUrl(uri);
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'multipart/form-data; boundary=$boundary',
      );

      _writeMultipartField(request, boundary, 'payload_json', jsonEncode(body));
      for (var index = 0; index < attachments.length; index++) {
        final attachment = attachments[index];
        request.write('--$boundary\r\n');
        request.write(
          'Content-Disposition: form-data; name="files[$index]"; '
          'filename="${attachment.name}"\r\n',
        );
        request.write('Content-Type: application/octet-stream\r\n\r\n');
        request.add(attachment.bytes);
        request.write('\r\n');
      }
      request.write('--$boundary--\r\n');

      final response = await request.close();
      return _readDiscordResponse(response);
    } finally {
      client.close(force: true);
    }
  }
}

void _writeMultipartField(
  HttpClientRequest request,
  String boundary,
  String name,
  String value,
) {
  request.write('--$boundary\r\n');
  request.write('Content-Disposition: form-data; name="$name"\r\n\r\n');
  request.write(value);
  request.write('\r\n');
}

String _attachmentName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final name = normalized.substring(normalized.lastIndexOf('/') + 1);
  final safeName = name.replaceAll(RegExp(r'["\r\n]'), '_');
  return safeName.isEmpty ? 'attachment' : safeName;
}

Future<RuntimeMap> _readDiscordResponse(HttpClientResponse response) async {
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
    DartDataInputSchema(
      label: 'Files',
      key: 'files',
      kind: DartDataInputKind.array,
      itemKind: DartDataInputKind.filePath,
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
  final body = <String, dynamic>{
    'content': message,
    if (config['username'] != null) 'username': config['username'],
    if (config['avatarUrl'] != null) 'avatar_url': config['avatarUrl'],
    if (config['tts'] != null) 'tts': config['tts'] == true,
  };
  final files = config['files'] is List
      ? (config['files'] as List)
            .map((file) => file.toString().trim())
            .where((file) => file.isNotEmpty)
            .toList()
      : <String>[];
  final response = files.isEmpty
      ? await transport.request(url, body)
      : transport.requestWithFiles == null
      ? throw UnsupportedError(
          'This Discord transport does not support file attachments.',
        )
      : await transport.requestWithFiles!(url, body, files);
  return {
    'sent': true,
    'message': message,
    if (files.isNotEmpty) 'files': files,
    if (response['statusCode'] != null) 'statusCode': response['statusCode'],
  };
}
