import '../schema/automation.dart';

final class ProviderSettingsValidation {
  const ProviderSettingsValidation(this.pluginId, this.errors);

  final String pluginId;
  final List<String> errors;

  bool get isValid => errors.isEmpty;
}

ProviderSettingsValidation validateProviderSettings(
  String pluginId,
  JsonMap settings,
) {
  final errors = <String>[];
  switch (pluginId) {
    case 'obs':
      final host = settings['host'];
      final port = settings['port'];
      if (host is! String || host.trim().isEmpty) {
        errors.add('Host is required.');
      }
      if (port is! num || port < 1 || port > 65535) {
        errors.add('Port must be between 1 and 65535.');
      }
    case 'youtube':
      if (!_has(settings, 'clientId')) {
        errors.add('Client ID is required.');
      }
      if (!_has(settings, 'clientSecret')) {
        errors.add('Client secret is required.');
      }
      if (!_has(settings, 'accessToken') && !_has(settings, 'refreshToken')) {
        errors.add('Access token or refresh token is required.');
      }
    case 'twitch':
      for (final field in [
        'clientId',
        'accessToken',
        'broadcasterId',
        'moderatorId',
      ]) {
        if (!_has(settings, field)) errors.add('$field is required.');
      }
    default:
      break;
  }
  return ProviderSettingsValidation(pluginId, List.unmodifiable(errors));
}

bool _has(JsonMap settings, String key) =>
    settings[key] is String && (settings[key] as String).trim().isNotEmpty;
