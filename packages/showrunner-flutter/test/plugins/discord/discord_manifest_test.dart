import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/discord/manifest.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';

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
}
