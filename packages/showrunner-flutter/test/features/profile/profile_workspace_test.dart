import 'dart:io';

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
}
