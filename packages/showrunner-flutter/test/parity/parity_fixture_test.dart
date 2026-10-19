import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/profile_repository.dart';
import 'package:showrunner_flutter/persistence/queue_config_repository.dart';
import 'package:showrunner_flutter/persistence/resource_repository.dart';
import 'package:showrunner_flutter/graph/domain/automation_document.dart';

void main() {
  const root = 'test/fixtures/parity';

  test(
    'loads the canonical automation fixtures as immutable graph documents',
    () async {
      for (final path in [
        '$root/automation_project/automation.json',
        '$root/immutable_document_project/automation.json',
      ]) {
        final value = jsonDecode(await File(path).readAsString());
        expect(value, isA<Map>());
        final automation = AutomationDocument.fromJson(
          Map<String, dynamic>.from(value as Map),
        );
        expect(automation.toJson()['schemaVersion'], 1);
      }
    },
  );

  test(
    'loads the canonical profile fixture with canonical nested automations',
    () async {
      final profile = await ProfileRepository(
        File('$root/profile_project/profile.json'),
      ).load();

      expect(profile?.name, 'Parity Profile');
      expect(profile?.activationAutomation.toJson()['schemaVersion'], 1);
      expect(profile?.deactivationAutomation.toJson()['schemaVersion'], 1);
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
