import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/resource_repository.dart';
import 'package:showrunner_flutter/persistence/secret_settings_store.dart';
import 'package:showrunner_flutter/plugins/bluesky/account_runtime.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  test(
    'signs in and keeps the Bluesky session out of the public resource',
    () async {
      final root = await Directory.systemTemp.createTemp('showrunner-bluesky-');
      addTearDown(() => root.delete(recursive: true));

      Future<List<int>> cipher(List<int> bytes) async =>
          bytes.map((byte) => byte ^ 0x5a).toList();
      final secretSettings = SecretSettingsStore(
        directory: Directory('${root.path}/secrets'),
        encrypt: cipher,
        decrypt: cipher,
      );
      final dataService = ShowRunnerDataService(
        root,
        secretSettings: secretSettings,
      );
      await dataService.savePluginSettings('bluesky', {
        'serviceUrl': 'https://bsky.social',
      });

      final service = BlueskyAccountAuthService(
        dataService: dataService,
        login: (identifier, appPassword) async => {
          'accessJwt': 'access-token',
          'refreshJwt': 'refresh-token',
          'did': 'did:plc:test',
          'handle': identifier,
          'passwordUsed': appPassword,
        },
      );

      final account = await service.signIn(
        accountId: 'main',
        identifier: 'user.test',
        appPassword: 'app-password',
        name: 'Main Bluesky',
      );

      expect(account.config['identifier'], 'user.test');
      expect(account.config['name'], 'Main Bluesky');
      expect(account.config['session'], isA<Map>());
      expect(account.state['authenticated'], isTrue);

      final repository = ResourceRepository(
        Directory('${root.path}/accounts/bluesky'),
        resourceType: 'BlueSkyAccount',
        secretSettings: secretSettings,
      );
      final persisted = await repository.load('main');
      expect(persisted?.config['session'], isA<Map>());
      expect(persisted?.config['session']['did'], 'did:plc:test');

      final publicFile = File('${root.path}/accounts/bluesky/main.json');
      final publicDocument = jsonDecode(await publicFile.readAsString()) as Map;
      expect((publicDocument['config'] as Map).containsKey('session'), isFalse);
    },
  );
}
