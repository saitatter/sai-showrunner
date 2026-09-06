import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/profile_repository.dart';
import 'package:showrunner_flutter/persistence/queue_config_repository.dart';
import 'package:showrunner_flutter/persistence/resource_repository.dart';
import 'package:showrunner_flutter/schema/automation.dart';

void main() {
  const root = 'test/fixtures/parity';

  test('loads the canonical automation fixtures as V2 documents', () async {
    for (final path in [
      '$root/automation_project/automation.json',
      '$root/strict_v2_project/automation.json',
    ]) {
      final value = jsonDecode(await File(path).readAsString());
      expect(value, isA<Map>());
      final automation = AutomationData.fromJson(
        Map<String, dynamic>.from(value as Map),
      );
      expect(automation.schemaVersion, 2);
    }
  });

  test(
    'loads the canonical profile fixture with V2 nested automations',
    () async {
      final profile = await ProfileRepository(
        File('$root/profile_project/profile.json'),
      ).load();

      expect(profile?.name, 'Parity Profile');
      expect(profile?.activationAutomation.schemaVersion, 2);
      expect(profile?.deactivationAutomation.schemaVersion, 2);
      expect(profile?.triggers.single['automation'], isA<Map>());
    },
  );

  test('loads canonical resources and queue configuration', () async {
    final resource = await ResourceRepository(
      Directory('$root/plugin_project'),
    ).load('twitch-channel');
    final overlay = await ResourceRepository(
      Directory('$root/overlay_project'),
    ).load('overlay');
    final queue = await QueueConfigRepository(
      Directory('$root/queue_project'),
    ).load(File('$root/queue_project/alerts.yaml'));

    expect(resource?.config['twitchId'], 'channel-42');
    expect(overlay?.config['widgets'], isA<List>());
    expect(queue.name, 'Alerts');
    expect(queue.gap.inMilliseconds, 250);
  });
}
