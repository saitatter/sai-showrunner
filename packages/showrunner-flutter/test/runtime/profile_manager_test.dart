import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/profile_repository.dart';
import 'package:showrunner_flutter/runtime/profile_manager.dart';
import 'package:showrunner_flutter/runtime/profile_runtime.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/schema/automation.dart';
import 'package:showrunner_flutter/schema/profile.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';

void main() {
  test(
    'starts and watches always profiles without opening the editor',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'profile-manager-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final events = StreamController<RuntimeMap>.broadcast();
      addTearDown(events.close);
      var executions = 0;
      final registry = DartPluginRegistry()
        ..register(
          DartPluginManifest(
            id: 'test',
            name: 'Test',
            actions: [
              DartActionDefinition(
                pluginId: 'test',
                actionId: 'record',
                invoke: (config, context) async {
                  executions++;
                  return null;
                },
              ),
            ],
            triggers: [
              DartTriggerDefinition(
                pluginId: 'test',
                triggerId: 'event',
                displayName: 'Event',
                listen: () => events.stream,
              ),
            ],
          ),
        );
      final profile = ShowRunnerProfile(
        name: 'Always',
        activationMode: 'always',
        triggers: [
          {
            'id': 'event-trigger',
            'plugin': 'test',
            'trigger': 'event',
            'config': {},
            'automation': AutomationData(
              graph: AutomationGraph(
                nodes: [
                  GraphNode(
                    id: 'record',
                    type: 'action',
                    x: 0,
                    y: 0,
                    data: {'plugin': 'test', 'action': 'record'},
                  ),
                ],
                entryNodeId: 'record',
              ),
            ).toJson(),
          },
        ],
        activationCondition: const {},
        activationAutomation: const AutomationData(),
        deactivationAutomation: const AutomationData(),
      );
      await ProfileRepository(
        File('${directory.path}/always.yaml'),
      ).save(profile);

      final runtime = DartProfileRuntime(registry: registry);
      final manager = DartProfileLifecycleManager(
        directory: directory,
        runtime: runtime,
      );
      addTearDown(manager.dispose);
      await manager.start();

      expect(runtime.isActive('always.yaml'), isTrue);
      events.add({});
      await Future<void>.delayed(Duration.zero);
      expect(executions, 1);
    },
  );

  test('reconciles conditional profiles when registry state changes', () async {
    final directory = await Directory.systemTemp.createTemp('profile-manager-');
    addTearDown(() => directory.delete(recursive: true));
    final registry = DartPluginRegistry()
      ..register(
        DartPluginManifest(
          id: 'test',
          name: 'Test',
          states: [
            const DartPluginStateDefinition(
              id: 'enabled',
              displayName: 'Enabled',
              initialValue: false,
            ),
          ],
        ),
      );
    final profile = ShowRunnerProfile(
      name: 'Conditional',
      activationMode: 'toggle',
      triggers: const [],
      activationCondition: {
        'type': 'value',
        'operator': 'equal',
        'lhs': {'type': 'state', 'plugin': 'test', 'state': 'enabled'},
        'rhs': {'type': 'value', 'value': true},
      },
      activationAutomation: const AutomationData(),
      deactivationAutomation: const AutomationData(),
    );
    await ProfileRepository(
      File('${directory.path}/conditional.yaml'),
    ).save(profile);

    final runtime = DartProfileRuntime(registry: registry);
    final manager = DartProfileLifecycleManager(
      directory: directory,
      runtime: runtime,
    );
    addTearDown(manager.dispose);
    await manager.start();
    expect(runtime.isActive('conditional.yaml'), isFalse);

    registry.updateState('test', 'enabled', true);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(runtime.isActive('conditional.yaml'), isTrue);
  });

  test('publishes trigger changes for an already active profile', () async {
    final directory = await Directory.systemTemp.createTemp('profile-manager-');
    addTearDown(() => directory.delete(recursive: true));
    final registry = DartPluginRegistry();
    final first = ShowRunnerProfile(
      name: 'Always',
      activationMode: 'always',
      triggers: [
        {
          'id': 'first-trigger',
          'plugin': 'test',
          'trigger': 'event',
          'config': {},
          'automation': const AutomationData().toJson(),
        },
      ],
      activationCondition: const {},
      activationAutomation: const AutomationData(),
      deactivationAutomation: const AutomationData(),
    );
    final file = File('${directory.path}/always.yaml');
    await ProfileRepository(file).save(first);
    final notifications = <List<JsonMap>>[];
    final runtime = DartProfileRuntime(registry: registry);
    final manager = DartProfileLifecycleManager(
      directory: directory,
      runtime: runtime,
      onActivityChanged: (id, {active = false, triggers = const []}) {
        if (active) notifications.add(List<JsonMap>.from(triggers));
      },
    );
    addTearDown(manager.dispose);
    await manager.start();
    expect(notifications.single.single['id'], 'first-trigger');

    final second = ShowRunnerProfile(
      name: first.name,
      activationMode: first.activationMode,
      triggers: [
        {...first.triggers.single, 'id': 'second-trigger'},
      ],
      activationCondition: first.activationCondition,
      activationAutomation: first.activationAutomation,
      deactivationAutomation: first.deactivationAutomation,
    );
    await ProfileRepository(file).save(second);
    await manager.refresh();

    expect(notifications.last.single['id'], 'second-trigger');
    expect(notifications, hasLength(2));
  });

  test(
    'isolates a profile activation failure from lifecycle startup',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'profile-manager-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final failingAutomation = AutomationData(
        graph: AutomationGraph(
          nodes: [
            GraphNode(
              id: 'missing-action',
              type: 'action',
              x: 0,
              y: 0,
              data: {'plugin': 'missing', 'action': 'action'},
            ),
          ],
          entryNodeId: 'missing-action',
        ),
      );
      await ProfileRepository(File('${directory.path}/broken.yaml')).save(
        ShowRunnerProfile(
          name: 'Broken',
          activationMode: 'always',
          triggers: const [],
          activationCondition: const {},
          activationAutomation: failingAutomation,
          deactivationAutomation: const AutomationData(),
        ),
      );

      final runtime = DartProfileRuntime(registry: DartPluginRegistry());
      final manager = DartProfileLifecycleManager(
        directory: directory,
        runtime: runtime,
      );
      addTearDown(manager.dispose);

      await expectLater(manager.start(), completes);
      expect(runtime.isActive('broken.yaml'), isFalse);
    },
  );
}
