import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/overlays/manifest.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/showrunner/manifest.dart';
import 'package:showrunner_flutter/persistence/automation_repository.dart';
import 'package:showrunner_flutter/persistence/profile_repository.dart';
import 'package:showrunner_flutter/persistence/queue_config_repository.dart';
import 'package:showrunner_flutter/persistence/resource_repository.dart';
import 'package:showrunner_flutter/runtime/action_queue.dart';
import 'package:showrunner_flutter/runtime/automation_queue_manager.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/runtime/graph_runtime.dart';
import 'package:showrunner_flutter/schema/automation.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';

const _fixtureRoot = 'test/fixtures/parity';

void main() {
  test('round-trips and executes the canonical automation fixture', () async {
    final root = await Directory.systemTemp.createTemp(
      'showrunner-parity-workflow-',
    );
    addTearDown(() => root.delete(recursive: true));

    final source = File('$_fixtureRoot/automation_project/automation.json');
    final automation = AutomationData.fromJson(
      Map<String, dynamic>.from(jsonDecode(await source.readAsString()) as Map),
    );
    final saved = AutomationRepository(File('${root.path}/automation.json'));
    await saved.save(automation);
    final reopened = await saved.loadStrict();
    expect(reopened?.toJson(), automation.toJson());

    final eventHub = DartPluginEventHub();
    final defaultQueue = DartActionQueue();
    late final DartPluginRegistry registry;
    final queueManager = DartAutomationQueueManager(
      defaultQueue: defaultQueue,
      execute: (queuedAutomation, context, _) =>
          const DartGraphRuntime().executeWithRegistry(
            graph: queuedAutomation.graph,
            context: context,
            registry: registry,
            dataWires: queuedAutomation.dataWires,
            subgraphs: queuedAutomation.subgraphs,
          ),
    );
    registry = DartPluginRegistry()
      ..register(createShowRunnerPlugin(queueManager: queueManager))
      ..register(createOverlaysPlugin(eventHub: eventHub));
    addTearDown(() async {
      await queueManager.dispose();
      await registry.close();
      await eventHub.dispose();
    });

    final broadcast = eventHub.stream(OverlayEventIds.broadcast).first;
    final result = await const DartGraphRuntime().executeWithRegistry(
      graph: reopened!.graph,
      context: EvaluationContext(
        contextState: {
          'event': {'message': 'fixture'},
        },
      ),
      registry: registry,
      dataWires: reopened.dataWires,
      subgraphs: reopened.subgraphs,
    );
    final overlayEvent = await broadcast;

    expect(result.completed, isTrue);
    expect(result.steps, 3);
    expect(result.nodeResults['queue-alert']?['queued'], isFalse);
    expect(overlayEvent['broadcastId'], 'showrunner_chat_message');
    expect(
      (overlayEvent['payload'] as Map)['message'],
      'Hello from the parity fixture',
    );
  });

  test(
    'round-trips the canonical profile, overlay, and queue fixtures',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'showrunner-parity-resources-',
      );
      addTearDown(() => root.delete(recursive: true));

      final profile = await ProfileRepository(
        File('$_fixtureRoot/profile_project/profile.json'),
      ).load();
      expect(profile, isNotNull);
      final profileRepository = ProfileRepository(
        File('${root.path}/profiles/profile.json'),
      );
      await profileRepository.save(profile!);
      expect((await profileRepository.load())?.toJson(), profile.toJson());

      final overlay = await ResourceRepository(
        Directory('$_fixtureRoot/overlay_project'),
      ).load('overlay');
      expect(overlay, isNotNull);
      final overlayRepository = ResourceRepository(
        Directory('${root.path}/overlays'),
      );
      await overlayRepository.save(overlay!);
      expect(
        (await overlayRepository.load('overlay'))?.toJson(),
        overlay.toJson(),
      );

      final sourceQueue = QueueConfigRepository(
        Directory('$_fixtureRoot/queue_project'),
      );
      final queue = await sourceQueue.load(
        File('$_fixtureRoot/queue_project/alerts.yaml'),
      );
      final queueRepository = QueueConfigRepository(
        Directory('${root.path}/queues'),
      );
      await queueRepository.save('alerts.yaml', queue);
      final reopenedQueue = await queueRepository.load(
        File('${root.path}/queues/alerts.yaml'),
      );
      expect(reopenedQueue.toJson(), queue.toJson());
    },
  );
}
