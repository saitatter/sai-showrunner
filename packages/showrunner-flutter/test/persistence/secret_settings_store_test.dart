import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/secret_settings_store.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  test(
    'round-trips encrypted secret settings without exposing plaintext',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'showrunner-secrets-',
      );
      addTearDown(() => directory.delete(recursive: true));
      Future<List<int>> cipher(List<int> bytes) async =>
          bytes.map((byte) => byte ^ 0x5a).toList();
      final store = SecretSettingsStore(
        directory: directory,
        encrypt: cipher,
        decrypt: cipher,
      );

      await store.save('twitch', {
        'accessToken': 'token-value',
        'refreshToken': 'refresh-value',
      });

      final raw = await File('${directory.path}/twitch.yaml').readAsString();
      expect(raw, isNot(contains('token-value')));
      expect(await store.load('twitch'), {
        'accessToken': 'token-value',
        'refreshToken': 'refresh-value',
      });
    },
  );

  test('splits declared secret settings from public plugin settings', () async {
    final directory = await Directory.systemTemp.createTemp(
      'showrunner-secrets-',
    );
    addTearDown(() => directory.delete(recursive: true));
    Future<List<int>> cipher(List<int> bytes) async =>
        bytes.map((byte) => byte ^ 0x5a).toList();
    final dataService = ShowRunnerDataService(
      directory,
      secretSettings: SecretSettingsStore(
        directory: Directory('${directory.path}/secrets'),
        encrypt: cipher,
        decrypt: cipher,
      ),
    );

    await dataService.savePluginSettings('twitch', {
      'clientId': 'public-client',
      'accessToken': 'private-token',
    });

    final publicText = await File(
      '${directory.path}/settings/twitch.yaml',
    ).readAsString();
    expect(publicText, contains('public-client'));
    expect(publicText, isNot(contains('private-token')));
    final secretText = await File(
      '${directory.path}/secrets/twitch.yaml',
    ).readAsBytes();
    expect(
      utf8.decode(secretText, allowMalformed: true),
      isNot(contains('private-token')),
    );
    expect(await dataService.loadPluginSettings('twitch'), {
      'clientId': 'public-client',
      'accessToken': 'private-token',
    });
  });
}
