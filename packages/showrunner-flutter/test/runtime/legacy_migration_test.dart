import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/editor/showrunner_graph_editor.dart';
import 'package:showrunner_flutter/persistence/automation_repository.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/runtime/graph_compiler.dart';
import 'package:showrunner_flutter/runtime/graph_runtime.dart';
import 'package:showrunner_flutter/schema/automation.dart';

void main() {
  test('converts legacy sequence actions into an executable graph', () async {
    final automation = AutomationData.fromJson({
      'name': 'Legacy alert',
      'sequence': {
        'actions': [
          {
            'id': 'first',
            'plugin': 'sample',
            'action': 'emit',
            'config': {'value': 'hello'},
            'resultMapping': {'value': 'lastValue'},
          },
          {
            'id': 'stack',
            'stack': [
              {
                'id': 'second',
                'plugin': 'sample',
                'action': 'emit',
                'config': {'value': 'world'},
              },
            ],
          },
          {
            'plugin': 'sample',
            'action': 'emit',
            'config': {'value': 'nested'},
            'subFlows': [
              {
                'actions': [
                  {
                    'plugin': 'sample',
                    'action': 'emit',
                    'config': {'value': 'done'},
                  },
                ],
              },
            ],
          },
        ],
      },
      'floatingSequences': [
        {
          'id': 'old-floating',
          'name': 'Old floating alert',
          'actions': [
            {
              'id': 'floating-action',
              'plugin': 'sample',
              'action': 'emit',
              'config': {'value': 'floating'},
            },
          ],
        },
      ],
      'variableNodes': [
        {'id': 'message', 'name': 'Message', 'type': 'string', 'value': ''},
      ],
      'dataWires': [
        {
          'id': 'legacy-wire',
          'fromNode': 'first',
          'fromPort': 'value',
          'toNode': 'legacy-action-3',
          'toPort': 'value',
        },
      ],
    });

    expect(automation.schemaVersion, 2);
    expect(automation.extra['name'], 'Legacy alert');
    expect(automation.graph.nodes.map((node) => node.id), [
      'first',
      'second',
      'legacy-action-3',
      'legacy-action-4',
    ]);
    expect(automation.graph.edges, hasLength(3));
    expect(automation.subgraphs.single.id, 'old-floating');
    expect(automation.subgraphs.single.nodes.single.id, 'floating-action');
    expect(automation.variableNodes.single['id'], 'message');
    expect(automation.dataWires.single.id, 'legacy-wire');
    expect(automation.graph.nodes[0].data['resultMapping'], {
      'value': 'lastValue',
    });
    expect(automation.toJson().containsKey('sequence'), isFalse);
    expect(automation.toJson().containsKey('floatingSequences'), isFalse);
    expect(automation.toJson()['subgraphs'], isNotEmpty);

    final registry = DartPluginRegistry()
      ..register(
        DartPluginManifest(
          id: 'sample',
          name: 'Sample',
          actions: [
            DartActionDefinition(
              pluginId: 'sample',
              actionId: 'emit',
              invoke: (config, context) async => {'value': config['value']},
            ),
          ],
        ),
      );
    final result = await const DartGraphRuntime().executeWithRegistry(
      graph: automation.graph,
      context: EvaluationContext(),
      registry: registry,
    );

    expect(result.completed, isTrue);
    expect(result.steps, 4);
    expect(result.contextState['lastValue'], 'hello');
    expect(result.nodeResults['legacy-action-4'], {'value': 'done'});
  });

  test('prefers an existing graph over a legacy sequence', () {
    final automation = AutomationData.fromJson({
      'graph': {
        'nodes': [
          {'id': 'graph-node', 'type': 'action', 'x': 0, 'y': 0},
        ],
        'edges': [],
        'entryNodeId': 'graph-node',
      },
      'sequence': {
        'actions': [
          {'plugin': 'sample', 'action': 'old'},
        ],
      },
    });

    expect(automation.graph.nodes.single.id, 'graph-node');
  });

  test(
    'round-trips a legacy fixture through migration and compiled runtime',
    () async {
      final fixture = File('test/fixtures/legacy/automation-roundtrip.yaml');
      final directory = await Directory.systemTemp.createTemp(
        'showrunner-legacy-roundtrip-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/automation.yaml');
      await file.writeAsString(await fixture.readAsString());
      final repository = AutomationRepository(file);

      final migrated = await repository.load();

      expect(migrated, isNotNull);
      expect(migrated!.schemaVersion, 2);
      expect(migrated.graph.nodes.map((node) => node.id), [
        'first',
        'stacked',
        'nested',
        'offset-child',
        'nested-child',
      ]);
      expect(migrated.graph.edges, hasLength(4));
      expect(migrated.subgraphs.single.id, 'floating');
      expect(migrated.variableNodes.single['id'], 'message');
      expect(migrated.dataWires.single.id, 'first-to-nested');

      final registry = DartPluginRegistry()
        ..register(
          DartPluginManifest(
            id: 'sample',
            name: 'Sample',
            actions: [
              DartActionDefinition(
                pluginId: 'sample',
                actionId: 'emit',
                invoke: (config, context) async => {'value': config['value']},
              ),
            ],
          ),
        );
      final compiled = const DartGraphCompiler().compileAutomation(migrated);
      final result = await const DartCompiledGraphRuntime().execute(
        graph: compiled,
        context: EvaluationContext(),
        action: (instruction, config, context) {
          final plugin = instruction.node.data['plugin']?.toString();
          final action = instruction.node.data['action']?.toString();
          if (plugin == null || action == null) {
            throw StateError('Fixture contains a non-action instruction.');
          }
          return registry.invokeAction(
            plugin,
            action,
            config,
            context: context,
          );
        },
      );

      expect(result.completed, isTrue);
      expect(result.steps, 5);
      expect(result.contextState['firstValue'], 'hello');
      expect(result.nodeResults['nested'], {'value': 'hello'});
      expect(result.nodeResults['nested-child'], {'value': 'child'});

      final persisted = jsonDecode(await file.readAsString()) as Map;
      expect(persisted['schemaVersion'], 2);
      expect(persisted.containsKey('sequence'), isFalse);
      expect(persisted.containsKey('floatingSequences'), isFalse);

      final reopened = await repository.load();
      expect(
        reopened?.graph.nodes.map((node) => node.id),
        migrated.graph.nodes.map((node) => node.id),
      );
      expect(reopened?.subgraphs.single.nodes.single.id, 'floating-action');
      expect(reopened?.dataWires.single.toNode, 'nested');

      final editor = ShowRunnerGraphEditor();
      addTearDown(editor.dispose);
      editor.loadAutomation(reopened!);
      expect(editor.controller.nodes, hasLength(6));
      expect(editor.invalidDataWires.map((wire) => wire.id), [
        'first-to-nested',
      ]);
      final editorSaved = editor.toAutomation(reopened);
      expect(editorSaved.variableNodes.single['id'], 'message');
      expect(editorSaved.dataWires.single.id, 'first-to-nested');
    },
  );
}
