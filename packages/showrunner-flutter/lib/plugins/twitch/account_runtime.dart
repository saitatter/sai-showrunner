import 'dart:io';

import '../../persistence/resource_repository.dart';
import '../../services/showrunner_data_service.dart';
import '../../schema/automation.dart';

/// Resolves the account resources used by the reference Twitch plugin.
///
/// Older Flutter profiles stored these values in `settings/twitch.yaml`, so
/// the settings map remains the fallback. Account resources win when present,
/// which makes imported `channel` and `bot` accounts operational without a
/// second manual configuration step.
Future<JsonMap> loadTwitchChannelSettings(
  ShowRunnerDataService dataService,
) async {
  final settings = await dataService.loadPluginSettings('twitch');
  final repository = ResourceRepository(
    Directory('${dataService.userDirectory.path}/accounts/twitch'),
    resourceType: 'TwitchAccount',
    secretSettings: dataService.secretSettingsStore,
  );
  final channel = await repository.load('channel');
  final bot = await repository.load('bot');
  if (channel == null && bot == null) return settings;

  final resolved = <String, dynamic>{...settings};
  if (channel != null) {
    _copyIfPresent(resolved, 'accessToken', channel.config['accessToken']);
    _copyIfPresent(resolved, 'refreshToken', channel.config['refreshToken']);
    _copyIfPresent(resolved, 'broadcasterId', channel.config['twitchId']);
  }
  if (bot != null) {
    _copyIfPresent(resolved, 'moderatorId', bot.config['twitchId']);
  }
  return resolved;
}

void _copyIfPresent(Map<String, dynamic> target, String key, Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isNotEmpty) target[key] = text;
}
