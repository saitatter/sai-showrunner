import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/runtime/profile_runtime.dart';
import 'package:showrunner_flutter/schema/automation.dart';
import 'package:showrunner_flutter/schema/profile.dart';

JsonMap _profileTrigger({
  required String id,
  required String plugin,
  required String trigger,
  required JsonMap graph,
  JsonMap config = const {},
}) => {
  'id': id,
  'plugin': plugin,
  'trigger': trigger,
  'config': config,
  'automation': {
    'schemaVersion': 2,
    'graph': graph,
    'subgraphs': [],
    'dataWires': [],
    'variableNodes': [],
    'triggerNodes': [],
  },
};

void main() {
  test('evaluates profile boolean groups and state values', () {
    final condition = <String, dynamic>{
      'type': 'group',
      'operator': 'and',
      'operands': [
        {
          'type': 'value',
          'operator': 'greaterThan',
          'lhs': {'type': 'state', 'plugin': 'twitch', 'state': 'viewers'},
          'rhs': {'type': 'value', 'value': 10},
        },
        {
          'type': 'value',
          'operator': 'equal',
          'lhs': {'type': 'value', 'value': 'live'},
          'rhs': {'type': 'value', 'value': 'live'},
        },
      ],
    };

    expect(
      evaluateBooleanCondition(
        condition,
        EvaluationContext(
          contextState: {
            'twitch': {'viewers': 12},
          },
        ),
      ),
      isTrue,
    );
  });

  test('runs activation and deactivation automations on transitions', () async {
    final calls = <String>[];
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
                calls.add(config['value'] as String);
                return null;
              },
            ),
          ],
        ),
      );
    GraphNode node(String id, String value) => GraphNode(
      id: id,
      type: 'action',
      x: 0,
      y: 0,
      data: {
        'plugin': 'test',
        'action': 'record',
        'config': {'value': value},
      },
    );
    AutomationData automation(String id, String value) => AutomationData(
      graph: AutomationGraph(nodes: [node(id, value)], entryNodeId: id),
    );
    final profile = ShowRunnerProfile(
      name: 'Main',
      activationMode: 'toggle',
      triggers: const [],
      activationCondition: {
        'type': 'group',
        'operator': 'or',
        'operands': [
          {
            'type': 'value',
            'operator': 'equal',
            'lhs': {'type': 'state', 'plugin': 'state', 'state': 'enabled'},
            'rhs': {'type': 'value', 'value': true},
          },
        ],
      },
      activationAutomation: automation('activate', 'activated'),
      deactivationAutomation: automation('deactivate', 'deactivated'),
    );
    final runtime = DartProfileRuntime(registry: registry);

    await runtime.reconcile(
      'main',
      profile,
      context: EvaluationContext(
        contextState: {
          'state': {'enabled': true},
        },
      ),
    );
    expect(calls, ['activated']);
    expect(runtime.isActive('main'), isTrue);

    await runtime.reconcile(
      'main',
      profile,
      context: EvaluationContext(
        contextState: {
          'state': {'enabled': false},
        },
      ),
    );
    expect(calls, ['activated', 'deactivated']);
    expect(runtime.isActive('main'), isFalse);
  });

  test('routes active trigger events to the matching inline graph', () async {
    final payloads = <dynamic>[];
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
                payloads.add(context.contextState['event']);
                return null;
              },
            ),
          ],
        ),
      );
    final profile = ShowRunnerProfile(
      name: 'Main',
      activationMode: 'always',
      triggers: [
        _profileTrigger(
          id: 'chat-trigger',
          plugin: 'test',
          trigger: 'chat',
          graph: {
            'nodes': [
              {
                'id': 'record',
                'type': 'action',
                'x': 0,
                'y': 0,
                'plugin': 'test',
                'action': 'record',
                'config': {},
              },
            ],
            'edges': [],
            'entryNodeId': 'record',
          },
        ),
      ],
      activationCondition: const {},
      activationAutomation: AutomationData(),
      deactivationAutomation: AutomationData(),
    );
    final runtime = DartProfileRuntime(registry: registry);
    await runtime.activate('main', profile);
    await runtime.handleTrigger('main', profile, 'test', 'chat', {
      'message': 'hi',
    });

    expect(payloads, [
      {'message': 'hi'},
    ]);
  });

  test(
    'routes multiple persisted trigger nodes to one executable graph',
    () async {
      final payloads = <dynamic>[];
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
                  payloads.add(context.contextState['event']);
                  return null;
                },
              ),
            ],
          ),
        );
      final profile = ShowRunnerProfile(
        name: 'Main',
        activationMode: 'always',
        triggers: [
          _profileTrigger(
            id: 'chat-trigger',
            plugin: 'test',
            trigger: 'chat',
            graph: {
              'nodes': [
                {
                  'id': 'record',
                  'type': 'action',
                  'x': 0,
                  'y': 0,
                  'plugin': 'test',
                  'action': 'record',
                  'config': {},
                },
              ],
              'entryNodeId': 'record',
            },
          ),
          _profileTrigger(
            id: 'keyword-trigger',
            plugin: 'test',
            trigger: 'keyword',
            graph: {
              'nodes': [
                {
                  'id': 'record',
                  'type': 'action',
                  'x': 0,
                  'y': 0,
                  'plugin': 'test',
                  'action': 'record',
                  'config': {},
                },
              ],
              'entryNodeId': 'record',
            },
          ),
        ],
        activationCondition: const {},
        activationAutomation: AutomationData(),
        deactivationAutomation: AutomationData(),
      );
      final runtime = DartProfileRuntime(registry: registry);
      await runtime.activate('main', profile);

      await runtime.handleTrigger('main', profile, 'test', 'chat', {
        'message': 'hello',
      });
      await runtime.handleTrigger('main', profile, 'test', 'keyword', {
        'word': 'launch',
      });

      expect(payloads, [
        {'message': 'hello'},
        {'word': 'launch'},
      ]);
    },
  );

  test('watch subscribes and disposes profile trigger streams', () async {
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
              triggerId: 'chat',
              displayName: 'Chat',
              listen: () => events.stream,
            ),
          ],
        ),
      );
    final profile = ShowRunnerProfile(
      name: 'Main',
      activationMode: 'always',
      triggers: [
        _profileTrigger(
          id: 'chat-trigger',
          plugin: 'test',
          trigger: 'chat',
          graph: {
            'nodes': [
              {
                'id': 'record',
                'type': 'action',
                'plugin': 'test',
                'action': 'record',
              },
            ],
            'entryNodeId': 'record',
          },
        ),
      ],
      activationCondition: const {},
      activationAutomation: AutomationData(),
      deactivationAutomation: AutomationData(),
    );
    final runtime = DartProfileRuntime(registry: registry);
    await runtime.activate('main', profile);
    final session = runtime.watch('main', profile);

    events.add({});
    await Future<void>.delayed(Duration.zero);
    expect(executions, 1);
    await session.dispose();
    events.add({});
    await Future<void>.delayed(Duration.zero);
    expect(executions, 1);
  });

  test('watch deduplicates repeated persisted trigger targets', () async {
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
              triggerId: 'chat',
              displayName: 'Chat',
              listen: () => events.stream,
            ),
          ],
        ),
      );
    final profile = ShowRunnerProfile(
      name: 'Main',
      activationMode: 'always',
      triggers: [
        _profileTrigger(
          id: 'chat-one',
          plugin: 'test',
          trigger: 'chat',
          graph: {
            'nodes': [
              {
                'id': 'record',
                'type': 'action',
                'plugin': 'test',
                'action': 'record',
              },
            ],
            'entryNodeId': 'record',
          },
        ),
        _profileTrigger(
          id: 'chat-two',
          plugin: 'test',
          trigger: 'chat',
          graph: {
            'nodes': [
              {
                'id': 'record',
                'type': 'action',
                'plugin': 'test',
                'action': 'record',
              },
            ],
            'entryNodeId': 'record',
          },
        ),
      ],
      activationCondition: const {},
      activationAutomation: AutomationData(),
      deactivationAutomation: AutomationData(),
    );
    final runtime = DartProfileRuntime(registry: registry);
    await runtime.activate('main', profile);
    final session = runtime.watch('main', profile);

    events.add({});
    await Future<void>.delayed(Duration.zero);
    expect(executions, 1);
    await session.dispose();
  });
}
