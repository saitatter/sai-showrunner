import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/profile_repository.dart';
import 'package:showrunner_flutter/schema/automation.dart';
import 'package:showrunner_flutter/schema/profile.dart';

void main() {
  test(
    'persists the profile trigger contract and activation condition',
    () async {
      final directory = await Directory.systemTemp.createTemp('profile-ui-');
      addTearDown(() => directory.delete(recursive: true));
      final profileFile = File('${directory.path}/profiles/main.yaml');
      final profile = ShowRunnerProfile(
        name: 'Main',
        activationMode: 'toggle',
        triggers: [
          {
            'id': 'trigger-1',
            'plugin': 'twitch',
            'trigger': 'chat',
            'config': {'user': 'alice'},
            'automation': AutomationData().toJson(),
          },
        ],
        activationCondition: {
          'type': 'group',
          'operator': 'or',
          'operands': const [],
        },
        activationAutomation: AutomationData(),
        deactivationAutomation: AutomationData(),
      );
      await ProfileRepository(profileFile).save(profile);
      final saved = await ProfileRepository(profileFile).load();
      expect(saved?.activationCondition['operator'], 'or');
      expect(saved!.triggers.single['plugin'], 'twitch');
      expect(saved.triggers.single['trigger'], 'chat');
      expect(saved.triggers.single['config'], {'user': 'alice'});
    },
  );

  test('upgrades legacy profile automations and writes a backup', () async {
    final directory = await Directory.systemTemp.createTemp(
      'profile-migration-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/profiles/legacy.yaml');
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'name': 'Legacy',
        'activationMode': 'toggle',
        'triggers': const [],
        'activationCondition': const {},
        'activationAutomation': {
          'sequence': {'actions': []},
        },
        'deactivationAutomation': {
          'sequence': {'actions': []},
        },
      }),
    );

    final profile = await ProfileRepository(file).load();

    expect(profile?.activationAutomation.schemaVersion, 2);
    expect(await Directory('${directory.path}/backup').exists(), isTrue);
    expect((await file.readAsString()).contains('sequence'), isFalse);
  });
}
