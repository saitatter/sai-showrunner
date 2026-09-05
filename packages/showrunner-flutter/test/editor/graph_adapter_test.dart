import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:sai_nodes/sai_nodes.dart';
import 'package:showrunner_flutter/components/data_inputs/data_input.dart';
import 'package:showrunner_flutter/editor/showrunner_graph_editor.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/runtime/automation_recovery.dart';
import 'package:showrunner_flutter/schema/automation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('round-trips graph links through the sai_nodes adapter', () {
    final editor = ShowRunnerGraphEditor();
    addTearDown(editor.dispose);
    editor.loadSampleGraph();
    final automation = editor.toAutomation(const AutomationData());

    expect(automation.graph.nodes, hasLength(3));
    expect(automation.graph.edges, hasLength(2));
    expect(automation.graph.edges, everyElement(isA<GraphEdge>()));
    final nodeIds = automation.graph.nodes.map((node) => node.id).toSet();
    expect(
      automation.graph.edges.every(
        (edge) =>
            nodeIds.contains(edge.from) &&
            nodeIds.contains(edge.to) &&
            edge.port == 'completed',
      ),
      isTrue,
    );
    final nodeTypes = {
      for (final node in automation.graph.nodes) node.id: node.type,
    };
    expect(
      automation.graph.edges.map(
        (edge) => '${nodeTypes[edge.from]} -> ${nodeTypes[edge.to]}',
      ),
      containsAll(<String>[
        'trigger.chatMessage -> queue.addItem',
        'queue.addItem -> overlay.pushChat',
      ]),
    );
    expect(validateAutomationGraph(automation), isEmpty);
  });

  test('surfaces rejected link feedback without creating an invalid link', () {
    final editor = ShowRunnerGraphEditor();
    addTearDown(editor.dispose);
    editor.loadSampleGraph();
    final triggerId = editor.controller.nodes.values
        .firstWhere((node) => node.prototype.idName == 'trigger.chatMessage')
        .id;
    final queueId = editor.controller.nodes.values
        .firstWhere((node) => node.prototype.idName == 'queue.addItem')
        .id;

    final link = editor.controller.addLink(
      triggerId,
      'payload',
      queueId,
      'exec',
    );

    expect(link, isNull);
    expect(editor.controller.links, hasLength(2));
    expect(editor.graphFeedback.value, contains('data port'));
  });

  test('preserves node configuration data through the graph adapter', () {
    final editor = ShowRunnerGraphEditor();
    addTearDown(editor.dispose);
    editor.loadAutomation(
      const AutomationData(
        graph: AutomationGraph(
          nodes: [
            GraphNode(
              id: 'action-1',
              type: 'queue.addItem',
              x: 10,
              y: 20,
              data: {
                'config': {'queue': 'alerts', 'message': 'hello'},
              },
            ),
          ],
          entryNodeId: 'action-1',
        ),
      ),
    );
    final saved = editor.toAutomation(const AutomationData());
    expect(saved.graph.nodes.single.data, {
      'config': {'queue': 'alerts', 'message': 'hello'},
    });
  });

  test('round-trips generic node instance title and size', () {
    final editor = ShowRunnerGraphEditor();
    addTearDown(editor.dispose);
    editor.loadAutomation(
      const AutomationData(
        graph: AutomationGraph(
          nodes: [
            GraphNode(
              id: 'action-1',
              type: 'queue.addItem',
              x: 10,
              y: 20,
              data: {
                'title': 'Alerts',
                'editorSize': [320, 180],
              },
            ),
          ],
          entryNodeId: 'action-1',
        ),
      ),
    );

    final editorNodeId = editor.editorNodeIdForSchema('action-1')!;
    final node = editor.controller.nodes[editorNodeId]!;
    expect(node.customTitle, 'Alerts');
    expect(node.customSize, const Size(320, 180));

    final saved = editor.toAutomation(const AutomationData());
    expect(saved.graph.nodes.single.data['title'], 'Alerts');
    expect(saved.graph.nodes.single.data['editorSize'], [320.0, 180.0]);
  });

  test('updates configuration for a selected node', () {
    final editor = ShowRunnerGraphEditor();
    addTearDown(editor.dispose);
    editor.loadAutomation(
      const AutomationData(
        graph: AutomationGraph(
          nodes: [GraphNode(id: 'action-1', type: 'action', x: 0, y: 0)],
          entryNodeId: 'action-1',
        ),
      ),
    );

    final editorNodeId = editor.editorNodeIdForSchema('action-1')!;
    editor.updateNodeConfig(editorNodeId, const {
      'duration': 30,
      'enabled': true,
    });

    expect(editor.nodeConfig(editorNodeId), {'duration': 30, 'enabled': true});
    expect(
      editor.toAutomation(const AutomationData()).graph.nodes.single.data,
      {
        'config': {'duration': 30, 'enabled': true},
      },
    );
  });

  test('creates built-in conversion nodes with Vue-compatible defaults', () {
    final editor = ShowRunnerGraphEditor();
    addTearDown(editor.dispose);

    editor.addNodeType('ShowRunner.convertStringToNumber');
    final nodeId = editor.controller.nodes.keys.single;

    expect(editor.nodeConfig(nodeId), {'value': '', 'fallback': 0});
    expect(editor.nodeData(nodeId)['resultMapping'], {
      'value': 'value',
      'converted': 'converted',
    });
  });

  test('creates result ports and identity mappings from action metadata', () {
    final registry = DartPluginRegistry()
      ..register(
        DartPluginManifest(
          id: 'sample',
          name: 'Sample',
          actions: [
            DartActionDefinition(
              pluginId: 'sample',
              actionId: 'measure',
              invoke: (config, context) async => {'score': 42},
              resultSchema: const DartDataInputSchema(
                label: '',
                kind: DartDataInputKind.object,
                fields: [
                  DartDataInputSchema(
                    label: 'Score',
                    key: 'score',
                    kind: DartDataInputKind.number,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    final editor = ShowRunnerGraphEditor(registry: registry);
    addTearDown(editor.dispose);

    final nodeId = editor.addNodeType('sample.measure')!;
    expect(editor.controller.nodes[nodeId]!.ports.keys, contains('score'));
    expect(editor.nodeResultMapping(nodeId), {'score': 'score'});

    editor.updateNodeResultMapping(nodeId, {'score': 'lastScore'});
    expect(editor.nodeResultMapping(nodeId), {'score': 'lastScore'});
    expect(
      editor
          .toAutomation(const AutomationData())
          .graph
          .nodes
          .single
          .data['resultMapping'],
      {'score': 'lastScore'},
    );
  });

  test('cycles through matching nodes when navigating search results', () {
    final editor = ShowRunnerGraphEditor();
    addTearDown(editor.dispose);
    editor.loadAutomation(
      const AutomationData(
        graph: AutomationGraph(
          nodes: [
            GraphNode(id: 'first', type: 'queue.addItem', x: 0, y: 0),
            GraphNode(id: 'second', type: 'queue.addItem', x: 100, y: 0),
            GraphNode(id: 'other', type: 'overlay.pushChat', x: 200, y: 0),
          ],
          entryNodeId: 'first',
        ),
      ),
    );
    editor.setSearchQuery('queue');
    final firstEditorId = editor.editorNodeIdForSchema('first')!;
    final secondEditorId = editor.editorNodeIdForSchema('second')!;

    expect(editor.searchResultCount(), 2);
    expect(editor.focusSearchResult(), secondEditorId);
    expect(editor.focusSearchResult(), firstEditorId);
    expect(editor.focusSearchResult(forward: false), secondEditorId);
  });

  test('tracks recent node types and accepts dynamic triggers', () {
    final editor = ShowRunnerGraphEditor();
    addTearDown(editor.dispose);

    editor.addNodeType('trigger.twitch.chat', title: 'Chat Message');
    editor.addNodeType('obs.scene', title: 'Change Scene');
    editor.addNodeType('trigger.twitch.chat', title: 'Chat Message');

    expect(editor.recentNodeTypes.value, ['trigger.twitch.chat', 'obs.scene']);
    expect(editor.currentGraphIssues(), isEmpty);
    final trigger = editor.controller.nodes.values.firstWhere(
      (node) => node.prototype.idName == 'trigger.twitch.chat',
    );
    expect(trigger.ports.keys, containsAll(<String>['completed', 'payload']));
    expect(trigger.ports.keys, isNot(contains('exec')));
  });

  test(
    'round-trips persisted trigger nodes separately from the executable graph',
    () {
      final editor = ShowRunnerGraphEditor();
      addTearDown(editor.dispose);
      editor.loadAutomation(
        const AutomationData(
          graph: AutomationGraph(
            nodes: [
              GraphNode(id: 'action-1', type: 'queue.addItem', x: 120, y: 40),
            ],
            entryNodeId: 'action-1',
          ),
          triggerNodes: [
            {
              'id': 'trigger-1',
              'plugin': 'twitch',
              'trigger': 'chat',
              'config': {'room': 'main'},
              'stop': true,
              'x': -240,
              'y': 40,
            },
          ],
        ),
      );

      final triggerId = editor.editorNodeIdForSchema('trigger-1');
      expect(triggerId, isNotNull);
      expect(
        editor.controller.nodes[triggerId!]!.prototype.idName,
        'trigger.twitch.chat',
      );

      final saved = editor.toAutomation(const AutomationData());
      expect(saved.graph.nodes.map((node) => node.id), ['action-1']);
      expect(saved.graph.entryNodeId, 'action-1');
      expect(saved.triggerNodes, [
        {
          'id': 'trigger-1',
          'plugin': 'twitch',
          'trigger': 'chat',
          'config': {'room': 'main'},
          'stop': true,
          'x': -256.0,
          'y': 64.0,
        },
      ]);
    },
  );

  test('serializes newly inserted dynamic triggers as trigger nodes', () {
    final editor = ShowRunnerGraphEditor();
    addTearDown(editor.dispose);

    editor.addNodeType('trigger.discord.message', title: 'Discord message');

    final saved = editor.toAutomation(const AutomationData());
    expect(saved.graph.nodes, isEmpty);
    expect(saved.triggerNodes, [
      {
        'id': saved.triggerNodes.single['id'],
        'plugin': 'discord',
        'trigger': 'message',
        'config': <String, dynamic>{},
        'stop': false,
        'x': 64.0,
        'y': 64.0,
      },
    ]);
  });

  test('resets trigger metadata when loading the sample graph', () {
    final editor = ShowRunnerGraphEditor();
    addTearDown(editor.dispose);
    editor.loadAutomation(
      const AutomationData(
        graph: AutomationGraph(nodes: [], entryNodeId: ''),
        triggerNodes: [
          {'id': 'persisted-trigger', 'plugin': 'twitch', 'trigger': 'chat'},
        ],
      ),
    );

    editor.loadSampleGraph();

    final saved = editor.toAutomation(const AutomationData());
    expect(saved.triggerNodes, isEmpty);
    expect(
      saved.graph.nodes.any((node) => node.type == 'trigger.chatMessage'),
      isTrue,
    );
  });

  test(
    'inserts regular actions after a node and reconnects downstream flow',
    () {
      final editor = ShowRunnerGraphEditor();
      addTearDown(editor.dispose);
      editor.loadSampleGraph();
      final queueId = editor.controller.nodes.values
          .firstWhere((node) => node.prototype.idName == 'queue.addItem')
          .id;

      final insertedId = editor.insertActionAfterNode('obs.scene', queueId)!;
      final saved = editor.toAutomation(const AutomationData());
      final insertedSchemaId = saved.graph.nodes
          .firstWhere((node) => node.id == insertedId)
          .id;
      final queueSchemaId = saved.graph.nodes
          .firstWhere((node) => node.type == 'queue.addItem')
          .id;
      final overlaySchemaId = saved.graph.nodes
          .firstWhere((node) => node.type == 'overlay.pushChat')
          .id;

      expect(
        saved.graph.edges.any(
          (edge) => edge.from == queueSchemaId && edge.to == insertedSchemaId,
        ),
        isTrue,
      );
      expect(
        saved.graph.edges.any(
          (edge) => edge.from == insertedSchemaId && edge.to == overlaySchemaId,
        ),
        isTrue,
      );
    },
  );

  test(
    'inserts terminal control flow without reconnecting downstream flow',
    () {
      for (final terminalType in const ['return', 'break', 'continue']) {
        final editor = ShowRunnerGraphEditor();
        editor.loadSampleGraph();
        final queueId = editor.controller.nodes.values
            .firstWhere((node) => node.prototype.idName == 'queue.addItem')
            .id;

        final insertedId = editor.insertControlFlowAfterNode(
          terminalType,
          queueId,
        );
        final saved = editor.toAutomation(const AutomationData());
        final queueSchemaId = saved.graph.nodes
            .firstWhere((node) => node.type == 'queue.addItem')
            .id;
        final overlaySchemaId = saved.graph.nodes
            .firstWhere((node) => node.type == 'overlay.pushChat')
            .id;

        expect(insertedId, isNotNull);
        expect(
          saved.graph.edges,
          contains(
            isA<GraphEdge>()
                .having((edge) => edge.from, 'from', queueSchemaId)
                .having((edge) => edge.to, 'to', insertedId),
          ),
        );
        expect(
          saved.graph.edges.any(
            (edge) => edge.from == queueSchemaId && edge.to == overlaySchemaId,
          ),
          isFalse,
        );
        expect(
          saved.graph.edges.any((edge) => edge.from == insertedId),
          isFalse,
        );
        editor.dispose();
      }
    },
  );

  test('inserts conversion actions as data-only nodes', () {
    final editor = ShowRunnerGraphEditor();
    addTearDown(editor.dispose);
    editor.loadSampleGraph();
    final triggerId = editor.controller.nodes.values
        .firstWhere((node) => node.prototype.idName == 'trigger.chatMessage')
        .id;

    final insertedId = editor.insertActionAfterNode(
      'ShowRunner.convertJsonStringToObject',
      triggerId,
    )!;
    final inserted = editor.controller.nodes[insertedId]!;
    final saved = editor.toAutomation(const AutomationData());

    expect(inserted.ports.keys, containsAll(<String>['value', 'converted']));
    expect(inserted.ports.keys, isNot(contains('exec')));
    expect(saved.graph.edges, hasLength(2));
    expect(
      saved.dataWires,
      contains(
        isA<DataWire>()
            .having((wire) => wire.toNode, 'toNode', insertedId)
            .having((wire) => wire.toPort, 'toPort', 'value'),
      ),
    );
  });

  test('inserts an action on a flow edge and reconnects both endpoints', () {
    final editor = ShowRunnerGraphEditor();
    addTearDown(editor.dispose);
    editor.loadSampleGraph();
    final queueId = editor.controller.nodes.values
        .firstWhere((node) => node.prototype.idName == 'queue.addItem')
        .id;
    final link = editor.controller.linksAsList.firstWhere(
      (candidate) => candidate.endpoints.sourceNodeId == queueId,
    );

    final insertedId = editor.insertActionOnFlowEdge(
      'obs.scene',
      link.id,
      offset: const Offset(640, 120),
    );

    expect(insertedId, isNotNull);
    expect(editor.controller.nodes[insertedId]!.offset, const Offset(640, 128));
    expect(
      editor.controller.linksAsList,
      contains(
        isA<LinkDataModel>().having(
          (value) => value.endpoints.sourceNodeId,
          'source',
          queueId,
        ),
      ),
    );
    expect(
      editor.controller.linksAsList,
      contains(
        isA<LinkDataModel>().having(
          (value) => value.endpoints.targetNodeId,
          'target',
          editor.controller.nodes.values
              .firstWhere((node) => node.prototype.idName == 'overlay.pushChat')
              .id,
        ),
      ),
    );
  });

  test('duplicates a configured selected action and reconnects its flow', () {
    final editor = ShowRunnerGraphEditor();
    addTearDown(editor.dispose);
    editor.loadAutomation(
      const AutomationData(
        graph: AutomationGraph(
          nodes: [
            GraphNode(
              id: 'first',
              type: 'action',
              x: 0,
              y: 0,
              data: {
                'plugin': 'obs',
                'action': 'scene',
                'config': {'scene': 'Starting soon'},
                'resultMapping': {'scene': 'lastScene'},
                'title': 'Original scene',
              },
            ),
            GraphNode(id: 'last', type: 'queue.addItem', x: 300, y: 0),
          ],
          edges: [GraphEdge(id: 'first-last', from: 'first', to: 'last')],
          entryNodeId: 'first',
        ),
      ),
    );

    final firstId = editor.editorNodeIdForSchema('first')!;
    editor.controller.selectNodesById({firstId});
    final duplicateId = editor.duplicateSelectedAction()!;
    final saved = editor.toAutomation(const AutomationData());
    final duplicate = saved.graph.nodes.firstWhere(
      (node) => node.id == duplicateId,
    );

    expect(duplicate.data['plugin'], 'obs');
    expect(duplicate.data['action'], 'scene');
    expect(duplicate.data['config'], {'scene': 'Starting soon'});
    expect(duplicate.data['resultMapping'], {'scene': 'lastScene'});
    expect(duplicate.data['title'], 'Original scene');
    expect(
      saved.graph.edges,
      contains(
        isA<GraphEdge>()
            .having((edge) => edge.from, 'from', 'first')
            .having((edge) => edge.to, 'to', duplicateId),
      ),
    );
    expect(
      saved.graph.edges,
      contains(
        isA<GraphEdge>()
            .having((edge) => edge.from, 'from', duplicateId)
            .having((edge) => edge.to, 'to', 'last'),
      ),
    );
  });

  test('restores action metadata through native cut and paste', () async {
    final editor = ShowRunnerGraphEditor();
    addTearDown(editor.dispose);
    editor.loadAutomation(
      const AutomationData(
        graph: AutomationGraph(
          nodes: [
            GraphNode(
              id: 'action-1',
              type: 'action',
              x: 0,
              y: 0,
              data: {
                'plugin': 'obs',
                'action': 'scene',
                'config': {'scene': 'Starting soon'},
                'title': 'Custom scene',
              },
            ),
          ],
          entryNodeId: 'action-1',
        ),
      ),
    );

    final actionId = editor.editorNodeIdForSchema('action-1')!;
    editor.controller.selectNodesById({actionId});
    await editor.cutSelection();
    expect(editor.controller.nodes, isEmpty);

    await editor.pasteSelection(position: const Offset(500, 100));
    final saved = editor.toAutomation(const AutomationData());
    final pasted = saved.graph.nodes.single;

    expect(pasted.id, isNot('action-1'));
    expect(pasted.data['plugin'], 'obs');
    expect(pasted.data['action'], 'scene');
    expect(pasted.data['config'], {'scene': 'Starting soon'});
    expect(pasted.data['title'], 'Custom scene');
  });

  test('restores trigger metadata through native cut and paste', () async {
    final editor = ShowRunnerGraphEditor();
    addTearDown(editor.dispose);

    editor.addNodeType('trigger.discord.message');
    final triggerId = editor.controller.nodes.keys.single;
    editor.updateNodeConfig(triggerId, {'channel': 'alerts'});
    editor.controller.selectNodesById({triggerId});

    await editor.cutSelection();
    await editor.pasteSelection(position: const Offset(500, 100));

    final saved = editor.toAutomation(const AutomationData());
    expect(saved.graph.nodes, isEmpty);
    expect(saved.triggerNodes, hasLength(1));
    expect(saved.triggerNodes.single['plugin'], 'discord');
    expect(saved.triggerNodes.single['trigger'], 'message');
    expect(saved.triggerNodes.single['config'], {'channel': 'alerts'});
  });

  test(
    'pastes multiple selected nodes with their internal flow link',
    () async {
      final editor = ShowRunnerGraphEditor();
      addTearDown(editor.dispose);
      editor.loadSampleGraph();
      final firstId = editor.controller.nodes.values
          .firstWhere((node) => node.prototype.idName == 'queue.addItem')
          .id;
      final secondId = editor.controller.nodes.values
          .firstWhere((node) => node.prototype.idName == 'overlay.pushChat')
          .id;
      final originalNodeIds = editor.controller.nodes.keys.toSet();
      editor.controller.selectNodesById({firstId, secondId});

      await editor.copySelection();
      editor.controller.clearSelection();
      await editor.pasteSelection(position: const Offset(640, 100));

      final saved = editor.toAutomation(const AutomationData());
      expect(saved.graph.nodes, hasLength(5));
      expect(saved.graph.edges, hasLength(3));
      final pastedNodeIds = saved.graph.nodes
          .map((node) => node.id)
          .where((id) => !originalNodeIds.contains(id))
          .toSet();
      expect(
        saved.graph.edges.any(
          (edge) =>
              pastedNodeIds.contains(edge.from) &&
              pastedNodeIds.contains(edge.to),
        ),
        isTrue,
      );
    },
  );

  test(
    'pastes internal data wires without changing trigger metadata',
    () async {
      final editor = ShowRunnerGraphEditor();
      addTearDown(editor.dispose);
      editor.loadAutomation(
        const AutomationData(
          graph: AutomationGraph(
            nodes: [
              GraphNode(id: 'trigger', type: 'trigger.chatMessage', x: 0, y: 0),
              GraphNode(id: 'action', type: 'queue.addItem', x: 320, y: 0),
            ],
            entryNodeId: 'trigger',
          ),
          dataWires: [
            DataWire(
              id: 'payload-wire',
              fromNode: 'trigger',
              fromPort: 'payload',
              toNode: 'action',
              toPort: 'payload',
            ),
          ],
        ),
      );
      final triggerId = editor.editorNodeIdForSchema('trigger')!;
      final actionId = editor.editorNodeIdForSchema('action')!;
      editor.controller.selectNodesById({triggerId, actionId});

      await editor.copySelection();
      editor.controller.clearSelection();
      await editor.pasteSelection(position: const Offset(640, 100));

      final saved = editor.toAutomation(const AutomationData());
      expect(saved.triggerNodes, isEmpty);
      expect(saved.dataWires, hasLength(2));
      expect(
        saved.dataWires.any(
          (wire) => wire.fromNode != 'trigger' && wire.toNode != 'action',
        ),
        isTrue,
      );
    },
  );

  test('inserts regular actions after a persisted trigger node', () {
    final editor = ShowRunnerGraphEditor();
    addTearDown(editor.dispose);
    editor.loadAutomation(
      const AutomationData(
        graph: AutomationGraph(
          nodes: [
            GraphNode(id: 'trigger-1', type: 'trigger.chatMessage', x: 0, y: 0),
            GraphNode(id: 'action-1', type: 'queue.addItem', x: 300, y: 0),
          ],
          edges: [
            GraphEdge(
              id: 'trigger-action',
              from: 'trigger-1',
              to: 'action-1',
              port: 'completed',
            ),
          ],
          entryNodeId: 'trigger-1',
        ),
      ),
    );

    final triggerId = editor.editorNodeIdForSchema('trigger-1')!;
    final insertedId = editor.insertActionAfterNode('obs.scene', triggerId)!;
    final saved = editor.toAutomation(const AutomationData());

    expect(saved.graph.entryNodeId, 'trigger-1');
    expect(
      saved.graph.edges,
      contains(
        isA<GraphEdge>()
            .having((edge) => edge.from, 'from', 'trigger-1')
            .having((edge) => edge.to, 'to', insertedId),
      ),
    );
    expect(
      saved.graph.edges,
      contains(
        isA<GraphEdge>()
            .having((edge) => edge.from, 'from', insertedId)
            .having((edge) => edge.to, 'to', 'action-1'),
      ),
    );
  });

  test('replaces a modern trigger in place and preserves its entry link', () {
    final editor = ShowRunnerGraphEditor();
    addTearDown(editor.dispose);
    editor.loadAutomation(
      const AutomationData(
        graph: AutomationGraph(
          nodes: [
            GraphNode(id: 'action-1', type: 'queue.addItem', x: 300, y: 0),
          ],
          entryNodeId: 'action-1',
        ),
        triggerNodes: [
          {
            'id': 'trigger-1',
            'plugin': 'twitch',
            'trigger': 'chat',
            'config': {'room': 'main'},
            'stop': true,
            'x': 0,
            'y': 0,
          },
        ],
      ),
    );
    final originalId = editor.editorNodeIdForSchema('trigger-1')!;
    final replacementId = editor.replaceTriggerNode(
      originalId,
      'trigger.discord.message',
      title: 'Discord message',
    )!;

    expect(replacementId, isNot(originalId));
    final saved = editor.toAutomation(const AutomationData());
    expect(saved.graph.nodes.map((node) => node.id), ['action-1']);
    expect(saved.triggerNodes.single['id'], 'trigger-1');
    expect(saved.triggerNodes.single['plugin'], 'discord');
    expect(saved.triggerNodes.single['trigger'], 'message');
    expect(saved.triggerNodes.single['config'], <String, dynamic>{});
    expect(saved.triggerNodes.single['stop'], isTrue);
    expect(
      editor.controller.linksAsList.any(
        (link) =>
            link.endpoints.sourceNodeId == replacementId &&
            link.endpoints.targetNodeId ==
                editor.editorNodeIdForSchema('action-1'),
      ),
      isTrue,
    );
  });

  test('replaces a trigger while preserving its metadata', () {
    final editor = ShowRunnerGraphEditor();
    addTearDown(editor.dispose);
    editor.loadAutomation(
      const AutomationData(
        graph: AutomationGraph(
          nodes: [
            GraphNode(
              id: 'trigger-1',
              type: 'trigger.chatMessage',
              x: 0,
              y: 0,
              data: {'stop': true},
            ),
            GraphNode(id: 'action-1', type: 'queue.addItem', x: 300, y: 0),
          ],
          edges: [
            GraphEdge(
              id: 'trigger-action',
              from: 'trigger-1',
              to: 'action-1',
              port: 'completed',
            ),
          ],
          entryNodeId: 'trigger-1',
        ),
      ),
    );
    final originalId = editor.editorNodeIdForSchema('trigger-1')!;
    editor.replaceTriggerNode(originalId, 'trigger.discord.message');

    final saved = editor.toAutomation(const AutomationData());
    expect(saved.triggerNodes, isEmpty);
    final trigger = saved.graph.nodes.firstWhere(
      (node) => node.id == 'trigger-1',
    );
    expect(trigger.type, 'trigger.discord.message');
    expect(trigger.data['stop'], isTrue);
    expect(saved.graph.entryNodeId, 'trigger-1');
  });

  test('moves selection to the nearest node in the requested direction', () {
    final editor = ShowRunnerGraphEditor();
    addTearDown(editor.dispose);
    editor.loadAutomation(
      const AutomationData(
        graph: AutomationGraph(
          nodes: [
            GraphNode(id: 'left', type: 'queue.addItem', x: 0, y: 0),
            GraphNode(id: 'right', type: 'overlay.pushChat', x: 300, y: 0),
            GraphNode(id: 'far-right', type: 'if', x: 700, y: 200),
          ],
          entryNodeId: 'left',
        ),
      ),
    );

    final leftId = editor.editorNodeIdForSchema('left')!;
    final rightId = editor.editorNodeIdForSchema('right')!;
    editor.controller.selectNodesById({leftId});

    expect(editor.moveSelection(LogicalKeyboardKey.arrowRight), rightId);
    expect(editor.controller.selectedNodeIds, {rightId});
    expect(
      editor.moveSelection(LogicalKeyboardKey.arrowDown, extendSelection: true),
      isNotNull,
    );
    expect(editor.controller.selectedNodeIds.length, 2);
  });

  test('preserves control-flow branch ports and configuration', () {
    final editor = ShowRunnerGraphEditor();
    addTearDown(editor.dispose);
    editor.loadAutomation(
      const AutomationData(
        graph: AutomationGraph(
          nodes: [
            GraphNode(
              id: 'condition',
              type: 'if',
              x: 0,
              y: 0,
              data: {
                'condition': {'type': 'literal', 'value': true},
              },
            ),
            GraphNode(id: 'then-node', type: 'action', x: 200, y: -80),
            GraphNode(id: 'else-node', type: 'action', x: 200, y: 80),
          ],
          edges: [
            GraphEdge(
              id: 'then-edge',
              from: 'condition',
              to: 'then-node',
              port: 'then',
            ),
            GraphEdge(
              id: 'else-edge',
              from: 'condition',
              to: 'else-node',
              port: 'else',
            ),
          ],
          entryNodeId: 'condition',
        ),
      ),
    );

    final conditionId = editor.editorNodeIdForSchema('condition')!;
    expect(
      editor.controller.nodes[conditionId]!.ports.keys,
      containsAll(<String>['exec', 'then', 'else']),
    );
    expect(editor.nodeData(conditionId)['condition'], {
      'type': 'literal',
      'value': true,
    });

    final saved = editor.toAutomation(const AutomationData());
    expect(
      saved.graph.edges.map((edge) => edge.port),
      containsAll(['then', 'else']),
    );
    expect(
      saved.graph.nodes
          .firstWhere((node) => node.data['condition'] != null)
          .data,
      {
        'condition': {'type': 'literal', 'value': true},
      },
    );
  });

  test('exposes loop ports and dynamic switch case ports', () {
    final editor = ShowRunnerGraphEditor();
    addTearDown(editor.dispose);
    editor.loadAutomation(
      const AutomationData(
        graph: AutomationGraph(
          nodes: [
            GraphNode(
              id: 'switch-node',
              type: 'switch',
              x: 0,
              y: 0,
              data: {
                'expression': {'type': 'variable', 'name': 'kind'},
                'cases': [
                  {'value': 'one', 'port': 'case:0'},
                  {'value': 'two', 'port': 'case:1'},
                ],
              },
            ),
            GraphNode(
              id: 'loop-node',
              type: 'forEach',
              x: 0,
              y: 160,
              data: {
                'variable': 'item',
                'collection': {'type': 'literal', 'value': []},
              },
            ),
          ],
          entryNodeId: 'switch-node',
        ),
      ),
    );

    final switchId = editor.editorNodeIdForSchema('switch-node')!;
    final loopId = editor.editorNodeIdForSchema('loop-node')!;
    expect(
      editor.controller.nodes[switchId]!.ports.keys,
      containsAll(<String>['exec', 'case:0', 'case:1', 'default']),
    );
    expect(
      editor.controller.nodes[loopId]!.ports.keys,
      containsAll(<String>['exec', 'body', 'next']),
    );

    final saved = editor.toAutomation(const AutomationData());
    expect(
      saved.graph.nodes.map((node) => node.type),
      containsAll(['switch', 'forEach']),
    );
    expect(
      saved.graph.nodes
          .firstWhere((node) => node.data['cases'] != null)
          .data['cases'],
      [
        {'value': 'one', 'port': 'case:0'},
        {'value': 'two', 'port': 'case:1'},
      ],
    );
  });

  test('exposes loaded subgraphs to the graph workspace', () {
    final editor = ShowRunnerGraphEditor();
    addTearDown(editor.dispose);
    editor.loadAutomation(
      const AutomationData(
        subgraphs: [
          SubgraphDefinition(
            id: 'welcome',
            name: 'Welcome flow',
            nodes: [],
            edges: [],
            entryNodeId: '',
            parameters: [
              {'name': 'viewer'},
            ],
            outputs: [
              {'name': 'message'},
            ],
          ),
        ],
      ),
    );

    expect(editor.subgraphs.value.single.name, 'Welcome flow');
    expect(editor.subgraphs.value.single.parameters.single['name'], 'viewer');
  });

  test('creates and serializes a new subgraph definition', () {
    final editor = ShowRunnerGraphEditor();
    addTearDown(editor.dispose);

    final id = editor.addSubgraph();

    expect(editor.subgraphs.value, hasLength(1));
    expect(editor.subgraphs.value.single.id, id);
    expect(editor.subgraphs.value.single.name, 'Subgraph 1');
    expect(editor.subgraphs.value.single.nodes, isEmpty);
    expect(editor.toAutomation(const AutomationData()).subgraphs.single.id, id);
  });

  test('deletes a subgraph and its main and nested call nodes', () {
    final editor = ShowRunnerGraphEditor();
    addTearDown(editor.dispose);
    editor.loadAutomation(
      const AutomationData(
        graph: AutomationGraph(
          nodes: [
            GraphNode(
              id: 'main-call',
              type: 'subgraphCall',
              x: 0,
              y: 0,
              data: {'subgraphId': 'target'},
            ),
            GraphNode(id: 'main-action', type: 'action', x: 100, y: 0),
          ],
          entryNodeId: 'main-call',
        ),
        subgraphs: [
          SubgraphDefinition(
            id: 'target',
            name: 'Target',
            nodes: [],
            edges: [],
            entryNodeId: '',
          ),
          SubgraphDefinition(
            id: 'other',
            name: 'Other',
            nodes: [
              GraphNode(
                id: 'nested-call',
                type: 'subgraphCall',
                x: 0,
                y: 0,
                data: {'subgraphId': 'target'},
              ),
            ],
            edges: [],
            entryNodeId: 'nested-call',
          ),
        ],
      ),
    );

    editor.deleteSubgraph('target');

    final saved = editor.toAutomation(const AutomationData());
    expect(saved.subgraphs.map((subgraph) => subgraph.id), ['other']);
    expect(
      saved.graph.nodes.map((node) => node.id),
      isNot(contains('main-call')),
    );
    expect(saved.subgraphs.single.nodes, isEmpty);
    expect(saved.subgraphs.single.entryNodeId, isEmpty);
  });

  test('adds a subgraph call node with target and inputs', () {
    final editor = ShowRunnerGraphEditor();
    addTearDown(editor.dispose);
    final subgraphId = editor.addSubgraph(name: 'Welcome');

    final nodeId = editor.addSubgraphCall(subgraphId);

    expect(nodeId, isNotNull);
    final savedNode = editor
        .toAutomation(const AutomationData())
        .graph
        .nodes
        .single;
    expect(savedNode.type, 'subgraphCall');
    expect(savedNode.data, {
      'subgraphId': subgraphId,
      'inputs': <String, dynamic>{},
      'title': 'Welcome',
    });
  });

  test('generates typed subgraph call ports from its contract', () {
    final editor = ShowRunnerGraphEditor();
    addTearDown(editor.dispose);
    final subgraphId = editor.addSubgraph(name: 'Format');
    editor.addSubgraphParameter(subgraphId);
    editor.addSubgraphParameter(subgraphId, output: true);

    final nodeId = editor.addSubgraphCall(subgraphId)!;
    final node = editor.controller.nodes[nodeId]!;

    expect(node.ports['input1'], isNotNull);
    expect(node.ports['output1'], isNotNull);
    expect(node.ports['input1']!.prototype.type, PortType.data);
    expect(node.ports['output1']!.prototype.type, PortType.data);
    expect(
      editor.toAutomation(const AutomationData()).graph.nodes.single.type,
      'subgraphCall',
    );

    editor.updateSubgraphParameter(
      subgraphId,
      0,
      field: 'name',
      value: 'message',
    );
    expect(node.ports['message'], isNotNull);
    expect(node.ports['input1'], isNull);
  });

  test(
    'navigates subgraphs and persists edits after returning to the parent graph',
    () {
      final editor = ShowRunnerGraphEditor();
      addTearDown(editor.dispose);
      editor.loadAutomation(
        const AutomationData(
          graph: AutomationGraph(
            nodes: [GraphNode(id: 'main-node', type: 'action', x: 0, y: 0)],
            entryNodeId: 'main-node',
          ),
          subgraphs: [
            SubgraphDefinition(
              id: 'welcome',
              name: 'Welcome',
              nodes: [
                GraphNode(id: 'child-node', type: 'action', x: 20, y: 30),
              ],
              edges: [],
              entryNodeId: 'child-node',
            ),
          ],
        ),
      );

      expect(editor.activeSubgraphId, isNull);
      expect(editor.enterSubgraph('welcome'), isTrue);
      expect(editor.activeSubgraphId, 'welcome');

      final childId = editor.editorNodeIdForSchema('child-node')!;
      editor.renameNode(childId, 'Welcome action');
      editor.addNodeType('overlay.pushChat', title: 'Follow-up');

      expect(editor.goBackToParentGraph(), isTrue);
      expect(editor.activeSubgraphId, isNull);

      final saved = editor.toAutomation(const AutomationData());
      final welcome = saved.subgraphs.single;
      expect(welcome.nodes, hasLength(2));
      expect(
        welcome.nodes.map((node) => node.data['title']),
        containsAll(<String>['Welcome action', 'Follow-up']),
      );
      expect(welcome.entryNodeId, 'child-node');

      expect(editor.enterSubgraph('welcome'), isTrue);
      expect(
        editor.nodeTitle(editor.editorNodeIdForSchema('child-node')!),
        'Welcome action',
      );
    },
  );

  test('renames a subgraph and persists the normalized name', () {
    final editor = ShowRunnerGraphEditor();
    addTearDown(editor.dispose);
    final subgraphId = editor.addSubgraph();

    editor.renameSubgraph(subgraphId, '  Welcome flow  ');

    expect(editor.subgraphs.value.single.name, 'Welcome flow');
    expect(
      editor.toAutomation(const AutomationData()).subgraphs.single.name,
      'Welcome flow',
    );
  });

  test('round-trips data wires through the sai_nodes adapter', () {
    final editor = ShowRunnerGraphEditor();
    addTearDown(editor.dispose);
    editor.loadAutomation(
      const AutomationData(
        graph: AutomationGraph(
          nodes: [
            GraphNode(id: 'trigger-1', type: 'trigger.chatMessage', x: 0, y: 0),
            GraphNode(id: 'action-1', type: 'queue.addItem', x: 100, y: 0),
          ],
          entryNodeId: 'trigger-1',
        ),
        dataWires: [
          DataWire(
            id: 'wire-1',
            fromNode: 'trigger-1',
            fromPort: 'payload',
            toNode: 'action-1',
            toPort: 'payload',
          ),
        ],
      ),
    );

    final wire = editor.toAutomation(const AutomationData()).dataWires.single;
    expect(wire.id, 'wire-1');
    expect(wire.fromNode, 'trigger-1');
    expect(wire.fromPort, 'payload');
    expect(wire.toNode, 'action-1');
    expect(wire.toPort, 'payload');
  });

  test('preserves nested subgraph data wires across navigation', () {
    final editor = ShowRunnerGraphEditor();
    addTearDown(editor.dispose);
    editor.loadAutomation(
      const AutomationData(
        subgraphs: [
          SubgraphDefinition(
            id: 'nested',
            name: 'Nested',
            nodes: [
              GraphNode(id: 'trigger', type: 'trigger.chatMessage', x: 0, y: 0),
              GraphNode(id: 'queue', type: 'queue.addItem', x: 120, y: 0),
            ],
            edges: [],
            dataWires: [
              DataWire(
                id: 'nested-wire',
                fromNode: 'trigger',
                fromPort: 'payload',
                toNode: 'queue',
                toPort: 'payload',
              ),
            ],
            entryNodeId: 'trigger',
          ),
        ],
      ),
    );

    expect(editor.enterSubgraph('nested'), isTrue);
    expect(editor.goBackToParentGraph(), isTrue);

    final nested = editor.toAutomation(const AutomationData()).subgraphs.single;
    expect(nested.dataWires.single.id, 'nested-wire');
  });

  test('loads, edits, and deletes variable nodes with their data wires', () {
    final editor = ShowRunnerGraphEditor();
    addTearDown(editor.dispose);
    editor.loadAutomation(
      const AutomationData(
        graph: AutomationGraph(
          nodes: [
            GraphNode(id: 'action-1', type: 'queue.addItem', x: 100, y: 0),
          ],
          entryNodeId: 'action-1',
        ),
        variableNodes: [
          {
            'id': 'message',
            'name': 'Message',
            'type': 'string',
            'value': 'hello',
            'x': 0,
            'y': 0,
          },
        ],
        dataWires: [
          DataWire(
            id: 'message-wire',
            fromNode: 'message',
            fromPort: 'value',
            toNode: 'action-1',
            toPort: 'payload',
          ),
        ],
      ),
    );

    final variableId = editor.editorNodeIdForSchema('message')!;
    expect(editor.isVariableNode(variableId), isTrue);
    editor.updateVariableNodeName(variableId, 'Updated message');
    editor.updateVariableNodeValue(variableId, 'updated');

    var saved = editor.toAutomation(const AutomationData());
    expect(saved.variableNodes.single, {
      'id': 'message',
      'name': 'Updated message',
      'type': 'string',
      'value': 'updated',
      'x': 0.0,
      'y': 0.0,
    });
    expect(saved.dataWires.single.id, 'message-wire');

    editor.deleteVariableNode(variableId);
    saved = editor.toAutomation(const AutomationData());
    expect(saved.variableNodes, isEmpty);
    expect(saved.dataWires, isEmpty);
  });

  test('retains invalid loaded edges for diagnostics and repair', () {
    final editor = ShowRunnerGraphEditor();
    addTearDown(editor.dispose);
    editor.loadAutomation(
      const AutomationData(
        graph: AutomationGraph(
          nodes: [
            GraphNode(id: 'condition', type: 'if', x: 0, y: 0),
            GraphNode(id: 'target', type: 'action', x: 200, y: 0),
          ],
          edges: [
            GraphEdge(
              id: 'invalid-flow',
              from: 'condition',
              to: 'target',
              port: 'missing',
            ),
          ],
          entryNodeId: 'condition',
        ),
      ),
    );

    expect(editor.invalidFlowEdges.single.id, 'invalid-flow');
    expect(
      editor.currentGraphIssues(),
      contains('Edge invalid-flow uses missing output port: condition.missing'),
    );
    expect(
      editor.toAutomation(const AutomationData()).graph.edges.single.id,
      'invalid-flow',
    );
  });

  test('discards individual retained invalid flow and data links', () {
    final editor = ShowRunnerGraphEditor();
    addTearDown(editor.dispose);
    editor.loadAutomation(
      const AutomationData(
        graph: AutomationGraph(
          nodes: [
            GraphNode(id: 'condition', type: 'if', x: 0, y: 0),
            GraphNode(id: 'target', type: 'action', x: 200, y: 0),
          ],
          edges: [
            GraphEdge(
              id: 'invalid-flow',
              from: 'condition',
              to: 'target',
              port: 'missing',
            ),
          ],
          entryNodeId: 'condition',
        ),
        dataWires: [
          DataWire(
            id: 'invalid-data',
            fromNode: 'condition',
            fromPort: 'missing',
            toNode: 'target',
            toPort: 'value',
          ),
        ],
      ),
    );

    editor.discardInvalidFlowEdge('invalid-flow');
    editor.discardInvalidDataWire('invalid-data');

    expect(editor.invalidFlowEdges, isEmpty);
    expect(editor.invalidDataWires, isEmpty);
    expect(editor.currentGraphIssues(), isEmpty);
    expect(editor.toAutomation(const AutomationData()).graph.edges, isEmpty);
    expect(editor.toAutomation(const AutomationData()).dataWires, isEmpty);
  });

  test('persists selected graph frames in automation metadata', () {
    final editor = ShowRunnerGraphEditor();
    addTearDown(editor.dispose);
    editor.loadSampleGraph();
    editor.controller.selectNodesById({editor.controller.nodes.keys.first});
    editor.frameSelection(title: 'Entry');

    final saved = editor.toAutomation(const AutomationData());
    expect(saved.extra['editorFrames'], hasLength(1));

    final restored = ShowRunnerGraphEditor();
    addTearDown(restored.dispose);
    restored.loadAutomation(saved);
    expect(restored.frames.value.single.title, 'Entry');
    expect(restored.frames.value.single.bounds.left, -472);
  });

  test('renames and deletes selected graph frames', () {
    final editor = ShowRunnerGraphEditor();
    addTearDown(editor.dispose);
    editor.loadSampleGraph();
    editor.controller.selectNodesById({editor.controller.nodes.keys.first});
    editor.frameSelection(title: 'Entry');

    final frame = editor.frames.value.single;
    editor.selectFrame(frame.id);
    editor.renameFrame(frame.id, '  Main path  ');
    expect(editor.frames.value.single.title, 'Main path');

    final saved = editor.toAutomation(const AutomationData());
    final restored = ShowRunnerGraphEditor();
    addTearDown(restored.dispose);
    restored.loadAutomation(saved);
    expect(restored.frames.value.single.id, frame.id);
    expect(restored.frames.value.single.title, 'Main path');

    restored.selectFrame(frame.id);
    restored.deleteSelectedFrame();
    expect(restored.frames.value, isEmpty);
    expect(
      restored.toAutomation(const AutomationData()).graph.nodes,
      hasLength(3),
    );
  });

  test('manages annotation frame members, color, movement, and metadata', () {
    final editor = ShowRunnerGraphEditor();
    addTearDown(editor.dispose);
    editor.loadAutomation(
      const AutomationData(
        graph: AutomationGraph(
          nodes: [
            GraphNode(id: 'first', type: 'action', x: 20, y: 30),
            GraphNode(id: 'second', type: 'action', x: 240, y: 30),
          ],
          entryNodeId: 'first',
        ),
      ),
    );

    final firstEditorId = editor.editorNodeIdForSchema('first')!;
    final secondEditorId = editor.editorNodeIdForSchema('second')!;
    editor.controller.selectNodesById({firstEditorId});
    editor.frameSelection(title: 'Inputs');
    final frame = editor.frames.value.single;
    editor.selectFrame(frame.id);
    editor.updateFrameColor(frame.id, '#22d3ee');

    editor.controller.clearSelection();
    editor.controller.selectNodesById({secondEditorId});
    editor.addSelectionToSelectedFrame();
    expect(
      editor.frames.value.single.nodeIds,
      containsAll(['first', 'second']),
    );

    editor.moveFrame(frame.id, const Offset(70, 70));
    expect(
      editor.controller.nodes[secondEditorId]!.offset,
      const Offset(320, 64),
    );

    editor.controller.clearSelection();
    editor.controller.selectNodesById({secondEditorId});
    editor.removeSelectionFromSelectedFrame();
    expect(editor.frames.value.single.nodeIds, ['first']);
    editor.clearSelectedFrameNodes();
    expect(editor.frames.value.single.nodeIds, isEmpty);

    final saved = editor.toAutomation(const AutomationData());
    final savedFrame = (saved.extra['editorFrames'] as List).single as Map;
    expect(savedFrame['title'], 'Inputs');
    expect(savedFrame['label'], 'Inputs');
    expect(savedFrame['color'], '#22d3ee');
    expect(savedFrame['nodeIds'], isEmpty);
  });

  test('moves selected nodes between annotation frames', () {
    final editor = ShowRunnerGraphEditor();
    addTearDown(editor.dispose);
    editor.loadAutomation(
      const AutomationData(
        graph: AutomationGraph(
          nodes: [
            GraphNode(id: 'first', type: 'queue.addItem', x: 0, y: 0),
            GraphNode(id: 'second', type: 'queue.addItem', x: 320, y: 0),
          ],
          entryNodeId: 'first',
        ),
      ),
    );

    final firstEditorId = editor.editorNodeIdForSchema('first')!;
    final secondEditorId = editor.editorNodeIdForSchema('second')!;
    editor.controller.selectNodesById({firstEditorId});
    editor.frameSelection(title: 'First');
    final firstFrame = editor.frames.value.single;
    editor.controller.clearSelection();
    editor.frameSelection(title: 'Second');
    final secondFrame = editor.frames.value.last;

    expect(editor.placeDraggedNodesInFrame(secondFrame.id, ['second']), isTrue);
    expect(editor.frameIdsForNodes(['second']), [secondFrame.id]);
    expect(editor.frameIdsForNodes(['first']), [firstFrame.id]);

    expect(editor.placeDraggedNodesInFrame(null, ['second']), isTrue);
    expect(editor.frameIdsForNodes(['second']), isEmpty);

    editor.controller.removeNodeById(secondEditorId);
    expect(
      editor.frames.value.every((frame) => !frame.nodeIds.contains('second')),
      isTrue,
    );
  });

  test('moves selected nodes out of older frames when creating a frame', () {
    final editor = ShowRunnerGraphEditor();
    addTearDown(editor.dispose);
    editor.loadAutomation(
      const AutomationData(
        graph: AutomationGraph(
          nodes: [GraphNode(id: 'node-1', type: 'queue.addItem', x: 0, y: 0)],
          entryNodeId: 'node-1',
        ),
      ),
    );

    final nodeId = editor.editorNodeIdForSchema('node-1')!;
    editor.controller.selectNodesById({nodeId});
    editor.frameSelection(title: 'Old');
    final oldFrame = editor.frames.value.single;
    editor.controller.selectNodesById({nodeId});
    editor.frameSelection(title: 'New');

    expect(
      editor.frames.value
          .firstWhere((frame) => frame.id == oldFrame.id)
          .nodeIds,
      isEmpty,
    );
    expect(editor.frames.value.last.nodeIds, ['node-1']);
  });

  test('tracks running, completed, and failed schema node execution', () {
    final editor = ShowRunnerGraphEditor();
    addTearDown(editor.dispose);
    editor.loadAutomation(
      const AutomationData(
        graph: AutomationGraph(
          nodes: [GraphNode(id: 'node-1', type: 'action', x: 0, y: 0)],
          entryNodeId: 'node-1',
        ),
      ),
    );

    final editorNodeId = editor.editorNodeIdForSchema('node-1')!;
    editor.markSchemaNodeRunning('node-1');
    expect(editor.activeNodeIds.value, contains(editorNodeId));
    expect(
      editor.executionStates.value[editorNodeId]?.status,
      GraphNodeExecutionStatus.running,
    );

    editor.markSchemaNodeCompleted('node-1');
    expect(editor.activeNodeIds.value, isEmpty);
    expect(
      editor.executionStates.value[editorNodeId]?.status,
      GraphNodeExecutionStatus.success,
    );

    editor.markSchemaNodeRunning('node-1');
    editor.markActiveSchemaNodeFailed(StateError('boom'));
    expect(
      editor.executionStates.value[editorNodeId]?.status,
      GraphNodeExecutionStatus.error,
    );
    expect(editor.executionStates.value[editorNodeId]?.error, contains('boom'));
  });

  test('persists renamed nodes and searches node metadata', () {
    final editor = ShowRunnerGraphEditor();
    addTearDown(editor.dispose);
    editor.loadSampleGraph();
    final nodeId = editor.controller.nodes.keys.first;

    editor.renameNode(nodeId, 'Entry trigger');
    editor.setSearchQuery('entry');

    expect(editor.searchNodeIds(), contains(nodeId));
    expect(
      editor
          .toAutomation(const AutomationData())
          .graph
          .nodes
          .firstWhere((node) => node.id == nodeId)
          .data['title'],
      'Entry trigger',
    );

    editor.clearExecutionStates();
    expect(editor.executionStates.value, isEmpty);
    expect(editor.activeNodeIds.value, isEmpty);
  });
}
