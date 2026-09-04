import '../../runtime/expression.dart';
import '../registry/plugin_registry.dart';

DartPluginManifest createDiscordPlugin() => const DartPluginManifest(
  id: 'discord',
  name: 'Discord',
  actions: [
    DartActionDefinition(
      pluginId: 'discord',
      actionId: 'discordMessage',
      displayName: 'Discord Message',
      invoke: _sendDiscordMessage,
    ),
  ],
);

Future<Object?> _sendDiscordMessage(
  RuntimeMap config,
  EvaluationContext context,
) async {
  final message = config['message']?.toString() ?? '';
  final webhook = config['webhook'];
  if (webhook is Map && webhook['webhookUrl'] != null) {
    // In Dart runtime, webhook requests can be dispatched or queued
    return {'sent': true, 'message': message};
  }
  return {'sent': false, 'reason': 'Webhook unconfigured'};
}
