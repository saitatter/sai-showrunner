import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/editor/showrunner_graph_editor.dart';
import 'package:showrunner_flutter/persistence/automation_repository.dart';
import 'package:showrunner_flutter/persistence/profile_repository.dart';
import 'package:showrunner_flutter/persistence/queue_config_repository.dart';
import 'package:showrunner_flutter/persistence/resource_repository.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/runtime/graph_runtime.dart';
import 'package:showrunner_flutter/runtime/graph_compiler.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/runtime/action_queue.dart';
import 'package:showrunner_flutter/schema/automation.dart';
import 'package:showrunner_flutter/schema/queue.dart';
import 'package:showrunner_flutter/schema/resource.dart';
import 'package:showrunner_flutter/schema/update.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';
import 'package:showrunner_flutter/services/structured_logger.dart';

void main() {
  test(
    'round-trips queue configuration with duration values and extra fields',
    () {
      const config = QueueConfig(
        name: 'Alerts',
        paused: true,
        gap: Duration(seconds: 2),
        timeout: Duration(seconds: 45),
        extra: {'custom': 'value'},
      );
      final restored = QueueConfig.fromJson(config.toJson());
      expect(restored.name, 'Alerts');
      expect(restored.paused, isTrue);
      expect(restored.gap, const Duration(seconds: 2));
      expect(restored.timeout, const Duration(seconds: 45));
      expect(restored.extra['custom'], 'value');
    },
  );

  test('persists queue configs and isolates malformed files', () async {
    final directory = await Directory.systemTemp.createTemp(
      'showrunner-queues-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final repository = QueueConfigRepository(directory);
    await repository.save(
      'alerts.yaml',
      const QueueConfig(name: 'Alerts', gap: Duration(seconds: 3)),
    );
    await File('${directory.path}/broken.yaml').writeAsString('not: [valid');

    final entries = await repository.list();
    expect(
      entries.map((entry) => entry.fileName),
      containsAll(<String>['alerts.yaml', 'broken.yaml']),
    );
    expect(
      entries
          .firstWhere((entry) => entry.fileName == 'alerts.yaml')
          .config
          ?.gap,
      const Duration(seconds: 3),
    );
    expect(
      entries.firstWhere((entry) => entry.fileName == 'broken.yaml').config,
      isNull,
    );

    await repository.delete('alerts.yaml');
    expect(await File('${directory.path}/alerts.yaml').exists(), isFalse);
  });

  test('uses configured queue gap and timeout defaults', () async {
    final queue = DartActionQueue(
      defaultGap: const Duration(milliseconds: 1),
      defaultTimeout: const Duration(seconds: 1),
    );
    addTearDown(queue.dispose);
    queue.enqueue({'name': 'one'}, {});
    queue.enqueue({'name': 'two'}, {});
    var executions = 0;
    await queue.processAll((_) async {
      executions++;
      return null;
    });
    expect(executions, 2);
  });

  test('builds a connected sample graph through the adapter', () {
    final editor = ShowRunnerGraphEditor()..loadSampleGraph();

    expect(editor.controller.nodes, hasLength(3));
    expect(editor.controller.project.projectData.links, hasLength(2));
    expect(
      editor.controller.nodes.values.map((node) => node.prototype.idName),
      containsAll(<String>[
        'trigger.chatMessage',
        'queue.addItem',
        'overlay.pushChat',
      ]),
    );

    editor.dispose();
  });

  test('compiles reachable graph nodes into a stable Dart instruction map', () {
    final graph = AutomationGraph.fromJson({
      'entryNodeId': 'start',
      'nodes': [
        {
          'id': 'start',
          'type': 'if',
          'condition': {'type': 'literal', 'value': true},
        },
        {'id': 'action', 'type': 'action'},
        {'id': 'done', 'type': 'return'},
        {'id': 'unreachable', 'type': 'action'},
      ],
      'edges': [
        {'id': 'e1', 'from': 'start', 'to': 'action', 'port': 'then'},
        {'id': 'e2', 'from': 'action', 'to': 'done'},
      ],
    });
    final compiled = const DartGraphCompiler().compile(graph);

    expect(compiled.entryIndex, 0);
    expect(compiled.instructions.map((item) => item.nodeId), [
      'start',
      'action',
      'done',
    ]);
    expect(
      compiled.instructionForNode('start').kind,
      GraphInstructionKind.branch,
    );
    expect(compiled.instructionForNode('action').outgoing, ['done']);
    expect(compiled.instructionForNode('start').targets['then'], 1);
  });

  test(
    'executes compiled branch targets with a bounded Dart runtime',
    () async {
      final graph = AutomationGraph.fromJson({
        'entryNodeId': 'start',
        'nodes': [
          {
            'id': 'start',
            'type': 'if',
            'condition': {'type': 'literal', 'value': true},
          },
          {
            'id': 'action',
            'type': 'action',
            'config': {'message': 'compiled'},
          },
          {'id': 'done', 'type': 'return'},
        ],
        'edges': [
          {'id': 'e1', 'from': 'start', 'to': 'action', 'port': 'then'},
          {'id': 'e2', 'from': 'action', 'to': 'done', 'port': 'completed'},
        ],
      });
      final compiled = const DartGraphCompiler().compile(graph);
      final result = await const DartCompiledGraphRuntime().execute(
        graph: compiled,
        context: EvaluationContext(),
        action: (instruction, config, context) async => {
          'message': config['message'],
        },
      );

      expect(result.completed, isTrue);
      expect(result.steps, 3);
      expect(result.nodeResults['action'], {'message': 'compiled'});
    },
  );

  test('executes a bounded compiled while loop', () async {
    final graph = AutomationGraph.fromJson({
      'entryNodeId': 'loop',
      'nodes': [
        {
          'id': 'loop',
          'type': 'while',
          'condition': {
            'type': 'binary',
            'op': '<',
            'left': {'type': 'variable', 'name': 'count'},
            'right': {'type': 'literal', 'value': 3},
          },
        },
        {'id': 'step', 'type': 'action'},
        {'id': 'done', 'type': 'return'},
      ],
      'edges': [
        {'id': 'body', 'from': 'loop', 'to': 'step', 'port': 'body'},
        {'id': 'repeat', 'from': 'step', 'to': 'loop'},
        {'id': 'next', 'from': 'loop', 'to': 'done', 'port': 'next'},
      ],
    });
    final compiled = const DartGraphCompiler().compile(graph);
    final result = await const DartCompiledGraphRuntime().execute(
      graph: compiled,
      context: EvaluationContext(locals: {'count': 0}),
      action: (instruction, config, context) async {
        context.locals['count'] = (context.locals['count'] as int) + 1;
        return {'count': context.locals['count']};
      },
    );

    expect(result.completed, isTrue);
    expect(result.steps, 8);
    expect(result.nodeResults['step'], {'count': 3});
  });

  test(
    'executes compiled subgraph call frames and reports debugger depth',
    () async {
      final automation = AutomationData.fromJson({
        'schemaVersion': 2,
        'graph': {
          'entryNodeId': 'call',
          'nodes': [
            {'id': 'call', 'type': 'subgraph', 'subgraphId': 'greeting'},
            {'id': 'done', 'type': 'return'},
          ],
          'edges': [
            {
              'id': 'complete',
              'from': 'call',
              'to': 'done',
              'port': 'completed',
            },
          ],
        },
        'subgraphs': [
          {
            'id': 'greeting',
            'name': 'Greeting',
            'entryNodeId': 'action',
            'nodes': [
              {
                'id': 'action',
                'type': 'action',
                'config': {'message': 'hello'},
              },
              {'id': 'return', 'type': 'return'},
            ],
            'edges': [
              {
                'id': 'done',
                'from': 'action',
                'to': 'return',
                'port': 'completed',
              },
            ],
          },
        ],
      });
      final compiled = const DartGraphCompiler().compileAutomation(automation);
      final depths = <int>[];
      final result = await const DartCompiledGraphRuntime().execute(
        graph: compiled,
        context: EvaluationContext(),
        onStep: (instruction, depth) => depths.add(depth),
        action: (instruction, config, context) async => {
          'message': config['message'],
        },
      );

      expect(result.completed, isTrue);
      expect(result.nodeResults['action'], {'message': 'hello'});
      expect(depths, [0, 1, 1, 0]);
    },
  );

  test('rejects automation data outside the V2 graph schema', () {
    expect(
      () => AutomationData.fromJson({
        'schemaVersion': 1,
        'graph': {'nodes': [], 'edges': [], 'entryNodeId': ''},
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'persists and loads automation JSON through the Dart repository',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'showrunner-flutter-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final repository = AutomationRepository(
        File('${directory.path}/automation.json'),
      );
      const automation = AutomationData(
        graph: AutomationGraph(
          nodes: [GraphNode(id: 'node-1', type: 'action', x: 10, y: 20)],
          entryNodeId: 'node-1',
        ),
      );

      await repository.save(automation);
      final loaded = await repository.load();

      expect(loaded?.schemaVersion, 2);
      expect(loaded?.graph.nodes.single.id, 'node-1');
      expect(loaded?.graph.entryNodeId, 'node-1');
    },
  );

  test('loads and saves plugin YAML settings with a health snapshot', () async {
    final directory = await Directory.systemTemp.createTemp('showrunner-data-');
    addTearDown(() => directory.delete(recursive: true));
    final service = ShowRunnerDataService(directory);

    await service.savePluginSettings('sample', {
      'enabled': true,
      'retryCount': 3,
      'label': 'Flutter runtime',
      'metadata': {
        'channels': ['chat', 'alerts'],
      },
    });
    final settings = await service.loadPluginSettings('sample');
    final health = await service.health();

    expect(settings, {
      'enabled': true,
      'retryCount': 3,
      'label': 'Flutter runtime',
      'metadata': {
        'channels': ['chat', 'alerts'],
      },
    });
    expect(health.isReady, isFalse);
    expect(health.settingsDirectoryExists, isTrue);
    expect(health.settingsFileCount, 1);

    await service.savePluginSettings('sample', {'enabled': false});
    expect(await service.loadPluginSettings('sample'), {'enabled': false});

    await service.updatePluginSetting('sample', 'newSetting', 42);
    expect(await service.loadPluginSettings('sample'), {
      'enabled': false,
      'newSetting': 42,
    });
  });

  test('loads resource configs from a user data directory', () async {
    final directory = await Directory.systemTemp.createTemp(
      'showrunner-resources-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final service = ShowRunnerDataService(directory);

    await service.saveResourceConfig('automations', 'welcome', {
      'name': 'Welcome',
      'enabled': true,
    });
    await File(
      '${directory.path}/automations/readme.txt',
    ).writeAsString('ignored');

    expect(await service.loadResourceConfigs('automations'), {
      'welcome': {'name': 'Welcome', 'enabled': true},
    });
  });

  test('evaluates graph expressions against Dart runtime context', () {
    final context = EvaluationContext(
      locals: {'count': 3},
      contextState: {
        'message': 'hello',
        'payload': {'amount': 7},
      },
      nodeResults: {
        'action-1': {'result': 4},
      },
    );

    expect(
      evaluateExpression({'type': 'variable', 'name': 'count'}, context),
      3,
    );
    expect(
      evaluateExpression({'type': 'variable', 'name': 'message'}, context),
      'hello',
    );
    expect(
      evaluateExpression({
        'type': 'binary',
        'op': '+',
        'left': {'type': 'variable', 'name': 'count'},
        'right': {'type': 'port', 'nodeId': 'action-1', 'port': 'result'},
      }, context),
      7,
    );
    expect(
      evaluateExpression({
        'type': 'call',
        'fn': 'includes',
        'args': [
          {
            'type': 'literal',
            'value': ['chat', 'alerts'],
          },
          {'type': 'literal', 'value': 'alerts'},
        ],
      }, context),
      isTrue,
    );
    expect(
      evaluateExpression({
        'type': 'member',
        'object': {'type': 'variable', 'name': 'payload'},
        'property': 'amount',
      }, context),
      7,
    );
    expect(
      () => evaluateExpression({
        'type': 'binary',
        'op': '/',
        'left': {'type': 'literal', 'value': 1},
        'right': {'type': 'literal', 'value': 0},
      }, context),
      throwsStateError,
    );
  });

  test('executes Dart graph actions and conditional flow', () async {
    final executed = <String>[];
    final graph = AutomationGraph(
      nodes: [
        const GraphNode(
          id: 'check',
          type: 'if',
          x: 0,
          y: 0,
          data: {
            'condition': {'type': 'variable', 'name': 'approved'},
          },
        ),
        const GraphNode(
          id: 'accepted',
          type: 'action',
          x: 100,
          y: 0,
          data: {
            'config': {'label': 'accepted'},
          },
        ),
        const GraphNode(
          id: 'rejected',
          type: 'action',
          x: 100,
          y: 100,
          data: {
            'config': {'label': 'rejected'},
          },
        ),
      ],
      edges: [
        const GraphEdge(
          id: 'then',
          from: 'check',
          to: 'accepted',
          port: 'then',
        ),
        const GraphEdge(
          id: 'else',
          from: 'check',
          to: 'rejected',
          port: 'else',
        ),
      ],
      entryNodeId: 'check',
    );

    final result = await const DartGraphRuntime().execute(
      graph: graph,
      context: EvaluationContext(contextState: {'approved': true}),
      action: (node, config, context) async {
        executed.add(config['label'] as String);
        return {'done': true};
      },
    );

    expect(result.completed, isTrue);
    expect(result.steps, 2);
    expect(executed, ['accepted']);
    expect(result.nodeResults['accepted'], {'done': true});
  });

  test('resolves data wires into action configuration', () async {
    RuntimeMap? receivedConfig;
    final graph = AutomationGraph(
      nodes: [
        const GraphNode(
          id: 'action-1',
          type: 'action',
          x: 0,
          y: 0,
          data: {
            'config': {'payload': {}},
          },
        ),
      ],
      entryNodeId: 'action-1',
    );

    final result = await const DartGraphRuntime().execute(
      graph: graph,
      context: EvaluationContext(contextState: {'message': 'hello'}),
      dataWires: const [
        DataWire(
          id: 'wire-1',
          fromNode: 'trigger',
          fromPort: 'message',
          toNode: 'action-1',
          toPort: 'payload.text',
        ),
      ],
      action: (node, config, context) async {
        receivedConfig = config;
        return null;
      },
    );

    expect(result.completed, isTrue);
    expect(receivedConfig, {
      'payload': {'text': 'hello'},
    });
  });

  test('emits node execution callbacks in traversal order', () async {
    final events = <String>[];
    final graph = AutomationGraph(
      nodes: const [
        GraphNode(id: 'first', type: 'action', x: 0, y: 0),
        GraphNode(id: 'second', type: 'action', x: 0, y: 0),
      ],
      edges: const [GraphEdge(id: 'edge', from: 'first', to: 'second')],
      entryNodeId: 'first',
    );

    await const DartGraphRuntime().execute(
      graph: graph,
      context: EvaluationContext(),
      action: (node, config, context) async => null,
      onNodeEnter: (nodeId) => events.add('enter:$nodeId'),
      onNodeExit: (nodeId) => events.add('exit:$nodeId'),
    );

    expect(events, [
      'enter:first',
      'exit:first',
      'enter:second',
      'exit:second',
    ]);
  });

  test('executes bounded forEach flow in Dart', () async {
    final values = <dynamic>[];
    final graph = AutomationGraph(
      nodes: [
        const GraphNode(
          id: 'loop',
          type: 'forEach',
          x: 0,
          y: 0,
          data: {
            'variable': 'item',
            'indexVariable': 'position',
            'collection': {'type': 'variable', 'name': 'items'},
          },
        ),
        const GraphNode(id: 'capture', type: 'action', x: 100, y: 0),
      ],
      edges: [
        const GraphEdge(id: 'body', from: 'loop', to: 'capture', port: 'body'),
        const GraphEdge(id: 'repeat', from: 'capture', to: 'loop'),
      ],
      entryNodeId: 'loop',
    );

    final result = await const DartGraphRuntime(maxSteps: 20).execute(
      graph: graph,
      context: EvaluationContext(
        contextState: {
          'items': ['a', 'b', 'c'],
        },
      ),
      action: (node, config, context) async {
        values.add(context.locals['item']);
        return null;
      },
    );

    expect(result.completed, isTrue);
    expect(values, ['a', 'b', 'c']);
  });

  test('maps action results into runtime context state', () async {
    final context = EvaluationContext();
    final graph = AutomationGraph(
      nodes: [
        const GraphNode(
          id: 'action-1',
          type: 'action',
          x: 0,
          y: 0,
          data: {
            'resultMapping': {'value': 'mappedValue'},
          },
        ),
      ],
      entryNodeId: 'action-1',
    );

    final result = await const DartGraphRuntime().execute(
      graph: graph,
      context: context,
      action: (node, config, runtimeContext) async => {'value': 42},
    );

    expect(context.contextState, isEmpty);
    expect(result.contextState, {'mappedValue': 42});
  });

  test('registers and invokes Dart plugin actions', () async {
    final registry = DartPluginRegistry();
    registry.register(
      DartPluginManifest(
        id: 'sample',
        name: 'Sample plugin',
        actions: [
          DartActionDefinition(
            pluginId: 'sample',
            actionId: 'echo',
            invoke: (config, context) async => config['value'],
          ),
        ],
      ),
    );
    const node = GraphNode(
      id: 'action-1',
      type: 'action',
      x: 0,
      y: 0,
      data: {
        'plugin': 'sample',
        'action': 'echo',
        'config': {'value': 'ok'},
      },
    );

    final result = await registry.invoke(node, EvaluationContext(), {
      'value': 'ok',
    });

    expect(result, 'ok');
    expect(registry.findAction('sample', 'echo'), isNotNull);

    final execution = await const DartGraphRuntime().executeWithRegistry(
      graph: const AutomationGraph(nodes: [node], entryNodeId: 'action-1'),
      context: EvaluationContext(),
      registry: registry,
    );
    expect(execution.nodeResults['action-1'], {'_result': 'ok'});
  });

  test('lists user files in stable order', () async {
    final directory = await Directory.systemTemp.createTemp(
      'showrunner-catalog-',
    );
    final service = ShowRunnerDataService(directory);
    await Directory('${directory.path}/profiles').create(recursive: true);
    await File(
      '${directory.path}/profiles/zeta.yaml',
    ).writeAsString('name: Zeta');
    await File(
      '${directory.path}/profiles/alpha.yaml',
    ).writeAsString('name: Alpha');

    expect(await service.listUserFiles('profiles'), [
      'alpha.yaml',
      'zeta.yaml',
    ]);
    await directory.delete(recursive: true);
  });

  test(
    'loads existing YAML automation files through the Dart repository',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'showrunner-automation-yaml-',
      );
      final file = File('${directory.path}/automation.yaml');
      await file.writeAsString('''
name: Existing automation
schemaVersion: 2
graph:
  nodes: []
  edges: []
  entryNodeId: ""
''');

      final automation = await AutomationRepository(file).load();

      expect(automation, isNotNull);
      expect(automation!.extra['name'], 'Existing automation');
      await directory.delete(recursive: true);
    },
  );

  test(
    'loads a profile with activation and deactivation automations',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'showrunner-profile-',
      );
      final file = File('${directory.path}/profile.yaml');
      await file.writeAsString('''
name: Main
activationMode: toggle
triggers: []
activationCondition:
  type: group
  operator: or
  operands: []
activationAutomation:
  schemaVersion: 2
  graph:
    nodes: []
    edges: []
    entryNodeId: ""
deactivationAutomation:
  schemaVersion: 2
  graph:
    nodes: []
    edges: []
    entryNodeId: ""
''');

      final profile = await ProfileRepository(file).load();

      expect(profile?.name, 'Main');
      expect(profile?.activationMode, 'toggle');
      expect(profile?.activationAutomation.graph.nodes, isEmpty);
      expect(profile?.deactivationAutomation.graph.nodes, isEmpty);
      await directory.delete(recursive: true);
    },
  );

  test('processes all queue items with a configured gap', () async {
    final queue = DartActionQueue();
    queue.enqueue({'type': 'one'}, {});
    queue.enqueue({'type': 'two'}, {});
    final processed = <String>[];

    await queue.processAll((item) async {
      processed.add(item.id);
      return null;
    }, gap: const Duration(milliseconds: 1));

    expect(processed, ['queue-0', 'queue-1']);
    expect(queue.pending, isEmpty);
    expect(queue.history, hasLength(2));
  });

  test('parses UpdateInfo and determines update availability', () {
    final update = UpdateInfo.fromJson({
      'version': '1.0.0-beta2',
      'releaseNotes': 'New feature release',
    }, currentVersion: '1.0.0-beta1');

    expect(update.hasUpdate, isTrue);
    expect(update.latestVersion, '1.0.0-beta2');
    expect(update.status, UpdateStatus.available);

    final upToDate = UpdateInfo.fromJson({
      'version': '1.0.0-beta1',
    }, currentVersion: '1.0.0-beta1');
    expect(upToDate.hasUpdate, isFalse);
    expect(upToDate.status, UpdateStatus.upToDate);
  });

  test('captures structured logs and notifies listeners', () async {
    final logger = ShowRunnerLogger.instance;
    logger.clear();
    final logs = <LogEntry>[];
    final subscription = logger.stream.listen(logs.add);

    logger.info('runtime', 'Runtime started');
    logger.error('plugin', 'Failed to connect', error: 'Connection refused');

    await Future<void>.delayed(Duration.zero);
    expect(logs, hasLength(2));
    expect(logs.first.message, 'Runtime started');
    expect(logs.last.level, LogLevel.error);
    await subscription.cancel();
  });

  test('persists and loads ResourceData through ResourceRepository', () async {
    final directory = await Directory.systemTemp.createTemp(
      'showrunner-resource-repo-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final repository = ResourceRepository(directory);

    const resource = ResourceData(
      id: 'res-1',
      config: {'name': 'Test Resource'},
    );
    await repository.save(resource);

    final list = await repository.list();
    expect(list, hasLength(1));
    expect(list.first.name, 'Test Resource');

    final loaded = await repository.load('res-1');
    expect(loaded?.id, 'res-1');

    await repository.delete('res-1');
    expect(await repository.load('res-1'), isNull);
  });

  test(
    'loads and edits YAML resources without creating duplicates',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'showrunner-yaml-resource-repo-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final yamlResource = File('${directory.path}/yaml-resource.yaml');
      await yamlResource.writeAsString('''
name: Overlay
width: 1920
widgets:
  - type: text
    text: Hello
''');
      final repository = ResourceRepository(directory);

      final loaded = await repository.load('yaml-resource');
      expect(loaded?.config['name'], 'Overlay');
      expect((loaded?.config['widgets'] as List).single['text'], 'Hello');

      await repository.save(
        ResourceData(
          id: 'yaml-resource',
          config: {...loaded!.config, 'name': 'Updated overlay'},
        ),
      );
      expect(await File('${directory.path}/yaml-resource.json').exists(), isFalse);
      expect((await repository.load('yaml-resource'))?.name, 'Updated overlay');
      expect((await directory.list().toList()), hasLength(1));
    },
  );

  testWidgets('mounts the deterministic navigation rail shell', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NavigationRail(
            selectedIndex: 0,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.account_tree),
                label: Text('Graph'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.extension),
                label: Text('Plugins'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.monitor_heart),
                label: Text('Diagnostics'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.bolt),
                label: Text('Automations'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.people_alt),
                label: Text('Profiles'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.layers),
                label: Text('Resources'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.receipt_long),
                label: Text('Logs'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.info),
                label: Text('About'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings),
                label: Text('Settings'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.rocket_launch),
                label: Text('Setup'),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Graph'), findsOneWidget);
    expect(find.text('Plugins'), findsOneWidget);
    expect(find.text('Resources'), findsOneWidget);
    expect(find.text('Logs'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Setup'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
