import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/resource_repository.dart';
import 'package:showrunner_flutter/persistence/secret_settings_store.dart';
import 'package:showrunner_flutter/services/oauth_token.dart';
import 'package:showrunner_flutter/plugins/twitch/account_runtime.dart';
import 'package:showrunner_flutter/schema/resource.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  test(
    'prefers imported channel and bot accounts over legacy plugin settings',
    () async {
      final root = await Directory.systemTemp.createTemp('showrunner-twitch-');
      addTearDown(() => root.delete(recursive: true));
      Future<List<int>> cipher(List<int> bytes) async =>
          bytes.map((byte) => byte ^ 0x5a).toList();
      final dataService = ShowRunnerDataService(
        root,
        secretSettings: SecretSettingsStore(
          directory: Directory('${root.path}/secrets'),
          encrypt: cipher,
          decrypt: cipher,
        ),
      );
      await dataService.savePluginSettings('twitch', {
        'clientId': 'client-id',
        'broadcasterId': 'old-channel',
        'accessToken': 'old-token',
      });
      final repository = ResourceRepository(
        Directory('${root.path}/accounts/twitch'),
        resourceType: 'TwitchAccount',
        secretSettings: dataService.secretSettingsStore,
      );
      await repository.save(
        const ResourceData(
          id: 'channel',
          config: {
            'name': 'Channel',
            'twitchId': 'channel-id',
            'accessToken': 'channel-token',
          },
        ),
      );
      await repository.save(
        const ResourceData(
          id: 'bot',
          config: {'name': 'Bot', 'twitchId': 'bot-id'},
        ),
      );

      expect(await loadTwitchChannelSettings(dataService), {
        'clientId': 'client-id',
        'broadcasterId': 'channel-id',
        'accessToken': 'channel-token',
        'moderatorId': 'bot-id',
      });
    },
  );

  test('authorizes and persists channel and bot account resources', () async {
    final root = await Directory.systemTemp.createTemp(
      'showrunner-twitch-auth-',
    );
    addTearDown(() => root.delete(recursive: true));
    Future<List<int>> cipher(List<int> bytes) async =>
        bytes.map((byte) => byte ^ 0x5a).toList();
    final dataService = ShowRunnerDataService(
      root,
      secretSettings: SecretSettingsStore(
        directory: Directory('${root.path}/secrets'),
        encrypt: cipher,
        decrypt: cipher,
      ),
    );
    await dataService.savePluginSettings('twitch', {
      'clientId': 'client-id',
      'clientSecret': 'client-secret',
    });
    final authorizations = <List<String>>[];
    final service = TwitchAccountAuthService(
      dataService: dataService,
      authorize:
          ({required clientId, required clientSecret, required scopes}) async {
            authorizations.add(scopes);
            return OAuthTokenSet(
              accessToken: scopes.contains('channel:manage:broadcast')
                  ? 'channel-token'
                  : 'bot-token',
              refreshToken: 'refresh-token',
            );
          },
      loadIdentity: (accessToken, clientId) async => {
        'id': accessToken == 'channel-token' ? 'channel-id' : 'bot-id',
        'displayName': accessToken == 'channel-token' ? 'Channel' : 'Bot',
        'email': '$accessToken@example.test',
        'broadcasterType': accessToken == 'channel-token' ? 'affiliate' : '',
      },
    );

    final channel = await service.authorizeAccount('channel');
    final bot = await service.authorizeAccount('bot');
    expect(channel.config['twitchId'], 'channel-id');
    expect(bot.config['twitchId'], 'bot-id');
    expect(authorizations, hasLength(2));
    expect(authorizations.first, contains('channel:manage:broadcast'));
    expect(authorizations.last, contains('chat:edit'));

    final repository = ResourceRepository(
      Directory('${root.path}/accounts/twitch'),
      resourceType: 'TwitchAccount',
      secretSettings: dataService.secretSettingsStore,
    );
    expect(
      (await repository.load('channel'))?.config['accessToken'],
      'channel-token',
    );
    expect((await repository.load('bot'))?.config['accessToken'], 'bot-token');
    final publicResource =
        jsonDecode(
              File(
                '${root.path}/accounts/twitch/channel.json',
              ).readAsStringSync(),
            )
            as Map;
    expect(
      (publicResource['config'] as Map).containsKey('accessToken'),
      isFalse,
    );
  });
}
