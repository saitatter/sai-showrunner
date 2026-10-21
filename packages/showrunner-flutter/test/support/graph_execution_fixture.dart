import 'package:flutter_test/flutter_test.dart';
import 'package:sai_nodes_core/sai_nodes_core.dart';
import 'package:showrunner_flutter/graph/domain/automation_document.dart';
import 'package:showrunner_flutter/graph/definitions/showrunner_graph_types.dart';
import 'package:showrunner_flutter/graph/runtime/graph_execution_engine.dart';
import 'package:showrunner_flutter/graph/runtime/graph_runtime.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/schema/data_input.dart';

AutomationDocument document(
  List<GraphNode> nodes,
  List<GraphConnection> connections, {
  required String entry,
  Map<String, AutomationSubgraph> subgraphs = const {},
  Map<String, GraphSpace> spaces = const {},
}) => AutomationDocument(
  graph: GraphDocument(
    id: 'test',
    spaces: {
      mainAutomationSpace: GraphSpace(
        id: mainAutomationSpace,
        nodes: {for (final node in nodes) node.id: node},
        connections: {for (final wire in connections) wire.id: wire},
      ),
      ...spaces,
    },
  ),
  settings: {'entryNodeId': entry},
  subgraphs: subgraphs,
);

GraphNode action(String id, {Object? value}) => GraphNode(
  id: id,
  type: actionNodeType('fixture', 'record'),
  data: {
    'config': {'value': value},
  },
);
GraphConnection flow(String from, String to, {String port = 'exec.out'}) =>
    GraphConnection(
      id: '$from/$port/$to',
      from: PortRef(nodeId: from, portId: port),
      to: PortRef(nodeId: to, portId: 'exec.in'),
      kind: GraphConnectionKind.control,
    );
GraphConnection wire(String from, String output, String to, String input) =>
    GraphConnection(
      id: '$from/$output/$to/$input',
      from: PortRef(nodeId: from, portId: output),
      to: PortRef(nodeId: to, portId: input),
      kind: GraphConnectionKind.data,
    );

Future<GraphExecutionResult> parity(
  AutomationDocument doc, {
  String entrySpaceId = mainAutomationSpace,
  String? entryNodeId,
  EvaluationContext Function()? context,
  List<List<Object?>>? runs,
}) async {
  final results = <GraphExecutionResult>[];
  final calls = <List<Object?>>[];
  for (final engine in <GraphExecutionEngine>[
    const InterpreterExecutionEngine(),
    CompiledExecutionEngine(),
  ]) {
    final recorded = <Object?>[];
    calls.add(recorded);
    final registry = DartPluginRegistry()
      ..register(
        DartPluginManifest(
          id: PluginId('fixture'),
          name: 'Fixture',
          triggers: [
            TriggerSpec<Map<String, dynamic>, Map<String, dynamic>>(
              pluginId: PluginId('fixture'),
              triggerId: TriggerId('message'),
              displayName: 'Message',
              listen: () => const Stream.empty(),
              eventSchema: const DartDataInputSchema(
                label: 'Event',
                kind: DartDataInputKind.object,
                fields: [
                  DartDataInputSchema(
                    key: 'text',
                    label: 'Text',
                    kind: DartDataInputKind.text,
                  ),
                ],
              ),
            ),
          ],
          actions: [
            ActionSpec<Map<String, dynamic>, Object?>(
              pluginId: PluginId('fixture'),
              actionId: ActionId('record'),
              configSchema: fixtureSchema,
              resultSchema: fixtureSchema,
              invoke: (config, context) async {
                recorded.add(config['value']);
                return {'value': config['value']};
              },
            ),
          ],
        ),
      );
    try {
      results.add(
        await engine.executeWithRegistry(
          automation: doc,
          context: context?.call() ?? EvaluationContext(),
          registry: registry,
          entrySpaceId: entrySpaceId,
          entryNodeId: entryNodeId,
        ),
      );
    } finally {
      await registry.close();
    }
  }
  expect(results.last.completed, results.first.completed);
  expect(results.last.nodeResults, results.first.nodeResults);
  expect(results.last.contextState, results.first.contextState);
  expect(results.last.outputValues, results.first.outputValues);
  expect(calls.last, calls.first);
  runs?.addAll(calls);
  return results.last;
}

const fixtureSchema = DartDataInputSchema(
  label: 'Record',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      key: 'value',
      label: 'Value',
      kind: DartDataInputKind.object,
      graphEditor: DartGraphEditorHints(dataType: 'core.any'),
    ),
  ],
);
