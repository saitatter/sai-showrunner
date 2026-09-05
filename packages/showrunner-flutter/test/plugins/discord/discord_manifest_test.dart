import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/discord/manifest.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'dart:convert';
import 'dart:io';

void main() {
  test('delivers a Discord webhook message through the transport', () async {
    String? url;
    dynamic body;
    final registry = DartPluginRegistry()
      ..register(
        createDiscordPlugin(
          transport: DiscordTransport((requestUrl, requestBody) async {
            url = requestUrl;
            body = requestBody;
            return {'statusCode': 204};
          }),
        ),
      );

    final result = await registry.invokeAction('discord', 'discordMessage', {
      'webhook': {'webhookUrl': 'https://discord.test/hooks/1'},
      'message': 'Hello from Flutter',
      'username': 'ShowRunner',
      'tts': true,
    });

    expect(url, 'https://discord.test/hooks/1');
    expect(body, {
      'content': 'Hello from Flutter',
      'username': 'ShowRunner',
      'tts': true,
    });
    expect(result, {
      'sent': true,
      'message': 'Hello from Flutter',
      'statusCode': 204,
    });
  });

  test(
    'does not call Discord when the webhook or message is missing',
    () async {
      var requests = 0;
      final registry = DartPluginRegistry()
        ..register(
          createDiscordPlugin(
            transport: DiscordTransport((url, body) async {
              requests++;
              return {'statusCode': 204};
            }),
          ),
        );

      final missingWebhook = await registry.invokeAction(
        'discord',
        'discordMessage',
        {'message': 'Hello'},
      );
      final missingMessage = await registry.invokeAction(
        'discord',
        'discordMessage',
        {
          'webhook': {'webhookUrl': 'https://discord.test/hooks/1'},
          'message': '  ',
        },
      );

      expect(missingWebhook, {'sent': false, 'reason': 'Webhook unconfigured'});
      expect(missingMessage, {'sent': false, 'reason': 'Message is empty'});
      expect(requests, 0);
    },
  );

  test('delivers configured files through the multipart transport', () async {
    String? url;
    RuntimeMap? body;
    List<String>? files;
    final registry = DartPluginRegistry()
      ..register(
        createDiscordPlugin(
          transport: DiscordTransport(
            (requestUrl, requestBody) async => {'statusCode': 204},
            requestWithFiles: (requestUrl, requestBody, requestFiles) async {
              url = requestUrl;
              body = requestBody;
              files = requestFiles;
              return {'statusCode': 204};
            },
          ),
        ),
      );

    final result = await registry.invokeAction('discord', 'discordMessage', {
      'webhook': {'webhookUrl': 'https://discord.test/hooks/1'},
      'message': 'See this file',
      'files': ['  C:\\media\\show.png  ', 'notes.txt'],
    });

    expect(url, 'https://discord.test/hooks/1');
    expect(body, {'content': 'See this file'});
    expect(files, ['C:\\media\\show.png', 'notes.txt']);
    expect(result, {
      'sent': true,
      'message': 'See this file',
      'files': ['C:\\media\\show.png', 'notes.txt'],
      'statusCode': 204,
    });
  });

  test('posts Discord files as multipart form data', () async {
    final directory = await Directory.systemTemp.createTemp('discord-test-');
    final attachment = File('${directory.path}/hello.txt')
      ..writeAsStringSync('attachment-body');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final transport = DiscordHttpTransport();
      final responseFuture = transport.requestWithFiles(
        'http://127.0.0.1:${server.port}/hooks/1',
        {'content': 'Hello multipart'},
        [attachment.path],
      );
      final incoming = await server.first;
      final requestBody = utf8.decode(
        await incoming.expand((chunk) => chunk).toList(),
      );
      final contentType = incoming.headers.contentType;

      expect(contentType?.mimeType, 'multipart/form-data');
      expect(contentType?.parameters['boundary'], isNotEmpty);
      expect(requestBody, contains('name="payload_json"'));
      expect(requestBody, contains('{"content":"Hello multipart"}'));
      expect(requestBody, contains('name="files[0]"; filename="hello.txt"'));
      expect(requestBody, contains('attachment-body'));

      incoming.response.statusCode = HttpStatus.noContent;
      await incoming.response.close();
      expect(await responseFuture, {'statusCode': HttpStatus.noContent});
    } finally {
      await server.close(force: true);
      await directory.delete(recursive: true);
    }
  });
}
