import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/resource_repository.dart';
import 'package:showrunner_flutter/persistence/secret_settings_store.dart';
import 'package:showrunner_flutter/plugins/wyze/account_runtime.dart';
import 'package:showrunner_flutter/schema/resource.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  test(
    'loads the imported main account and writes refreshed tokens to it',
    () async {
      final root = await Directory.systemTemp.createTemp('showrunner-wyze-');
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
      await dataService.savePluginSettings('wyze', {'keyId': 'key-id'});
      final repository = ResourceRepository(
        Directory('${root.path}/accounts/wyze'),
        resourceType: 'WyzeAccount',
        secretSettings: dataService.secretSettingsStore,
      );
      await repository.save(
        const ResourceData(
          id: 'main',
          config: {'name': 'Wyze', 'email': 'owner@example.test'},
        ),
      );
      await repository.save(
        const ResourceData(
          id: 'main',
          config: {
            'name': 'Wyze',
            'email': 'owner@example.test',
            'accessToken': 'old-token',
            'refreshToken': 'old-refresh',
          },
        ),
      );

      expect(await loadWyzeAccountSettings(dataService), {
        'keyId': 'key-id',
        'email': 'owner@example.test',
        'accessToken': 'old-token',
        'refreshToken': 'old-refresh',
      });

      await saveWyzeAccountTokens(
        dataService,
        accessToken: 'new-token',
        refreshToken: 'new-refresh',
      );
      final loaded = await repository.load('main');
      expect(loaded?.config['accessToken'], 'new-token');
      expect(loaded?.config['refreshToken'], 'new-refresh');
    },
  );
}
