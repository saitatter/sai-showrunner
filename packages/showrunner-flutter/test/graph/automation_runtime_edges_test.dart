import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/graph/runtime/graph_execution_engine.dart';
import 'package:showrunner_flutter/graph/runtime/production_graph_vm.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/runtime/cancellation.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/schema/data_input.dart';
import '../support/graph_fixtures.dart';

void main() {
  test(
    'production program keeps its explicit sixteen-opcode instruction set',
    () {
      expect(DartGraphOpCode.values, hasLength(16));
    },
  );
  for (final compiled in [false, true]) {
    GraphExecutionEngine engine() => compiled
        ? CompiledExecutionEngine(maxCallDepth: 2)
        : const InterpreterExecutionEngine(maxDepth: 2);
    test(
      '${compiled ? 'VM' : 'interpreter'} routes scalar, array and null results through result ports',
      () async {
        for (final value in <Object?>[
          42,
          [1, 2],
          null,
          true,
          'text',
        ]) {
          final registry = DartPluginRegistry()
            ..register(
              DartPluginManifest(
                id: PluginId('test'),
                name: 'Result fixtures',
                actions: [
                  ActionSpec<Map<String, dynamic>, Object?>(
                    pluginId: PluginId('test'),
                    actionId: ActionId('source'),
                    resultSchema: const DartDataInputSchema(
                      label: 'Result',
                      kind: DartDataInputKind.text,
                      graphEditor: DartGraphEditorHints(dataType: 'core.any'),
                    ),
                    invoke: (config, context) async => value,
                  ),
                  ActionSpec<Map<String, dynamic>, Object?>(
                    pluginId: PluginId('test'),
                    actionId: ActionId('record'),
                    configSchema: const DartDataInputSchema(
                      label: 'Config',
                      kind: DartDataInputKind.object,
                      fields: [
                        DartDataInputSchema(
                          key: 'value',
                          label: 'Value',
                          kind: DartDataInputKind.text,
                          graphEditor: DartGraphEditorHints(
                            dataType: 'core.any',
                          ),
                        ),
                      ],
                    ),
                    invoke: (config, context) async => {
                      'value': config['value'],
                    },
                  ),
                ],
              ),
            );
          try {
            final result = await engine().executeWithRegistry(
              automation: automationFixture(
                nodes: [
                  actionFixture('source', action: 'source'),
                  actionFixture('target'),
                ],
                connections: [
                  controlFixture('next', 'source', 'target'),
                  valueFixture(
                    'value',
                    'source',
                    'result:_result',
                    'target',
                    'config:value',
                  ),
                ],
                entryNodeId: 'source',
              ),
              context: EvaluationContext(),
              registry: registry,
            );
            expect(result.nodeResults['target'], {'value': value});
          } finally {
            await registry.close();
          }
        }
      },
    );
    test(
      '${compiled ? 'VM' : 'interpreter'} bounds recursive calls using actual space IDs',
      () async {
        final signature = AutomationSubgraph(
          id: 'recursive',
          name: 'Recursive',
          entryNodeId: 'nested-call',
        );
        final document = automationFixture(
          nodes: [
            GraphNode(
              id: 'main-call',
              type: 'showrunner.subgraphCall',
              data: {'subgraphId': signature.id},
            ),
          ],
          entryNodeId: 'main-call',
          subgraphs: {signature.id: signature},
          spaces: {
            signature.spaceId: GraphSpace(
              id: signature.spaceId,
              nodes: {
                'nested-call': GraphNode(
                  id: 'nested-call',
                  type: 'showrunner.subgraphCall',
                  data: {'subgraphId': signature.id},
                ),
              },
            ),
          },
        );
        final registry = DartPluginRegistry();
        addTearDown(registry.close);
        await expectLater(
          engine().executeWithRegistry(
            automation: document,
            context: EvaluationContext(),
            registry: registry,
          ),
          throwsStateError,
        );
      },
    );
    test(
      '${compiled ? 'VM' : 'interpreter'} propagates action cancellation out of subgraph and loop',
      () async {
        final token = DartCancellationToken();
        var invoked = 0;
        final registry = DartPluginRegistry()
          ..register(
            DartPluginManifest(
              id: PluginId('test'),
              name: 'Cancellation fixture',
              actions: [
                ActionSpec<Map<String, dynamic>, Object?>(
                  pluginId: PluginId('test'),
                  actionId: ActionId('cancel'),
                  invoke: (config, context) async {
                    invoked++;
                    context.cancellationToken!.cancel();
                    return null;
                  },
                ),
              ],
            ),
          );
        addTearDown(registry.close);
        final signature = AutomationSubgraph(
          id: 'cancel',
          name: 'Cancel',
          entryNodeId: 'cancel-action',
        );
        final document = automationFixture(
          nodes: [
            GraphNode(
              id: 'loop',
              type: 'showrunner.for',
              data: {'start': 0, 'end': 3, 'step': 1},
            ),
            GraphNode(
              id: 'call',
              type: 'showrunner.subgraphCall',
              data: {'subgraphId': signature.id},
            ),
          ],
          connections: [
            controlFixture('body', 'loop', 'call', port: 'flow:body'),
          ],
          entryNodeId: 'loop',
          subgraphs: {signature.id: signature},
          spaces: {
            signature.spaceId: GraphSpace(
              id: signature.spaceId,
              nodes: {
                'cancel-action': actionFixture(
                  'cancel-action',
                  action: 'cancel',
                ),
              },
            ),
          },
        );
        await expectLater(
          engine().executeWithRegistry(
            automation: document,
            context: EvaluationContext(cancellationToken: token),
            registry: registry,
          ),
          throwsA(isA<DartCancelledException>()),
        );
        expect(invoked, 1);
      },
    );
    test(
      '${compiled ? 'VM' : 'interpreter'} propagates action failure without running following nodes',
      () async {
        var invoked = 0;
        final registry = DartPluginRegistry()
          ..register(
            DartPluginManifest(
              id: PluginId('test'),
              name: 'Failure fixture',
              actions: [
                ActionSpec<Map<String, dynamic>, Object?>(
                  pluginId: PluginId('test'),
                  actionId: ActionId('fail'),
                  invoke: (config, context) async =>
                      throw StateError('expected action failure'),
                ),
                ActionSpec<Map<String, dynamic>, Object?>(
                  pluginId: PluginId('test'),
                  actionId: ActionId('record'),
                  invoke: (config, context) async {
                    invoked++;
                    return null;
                  },
                ),
              ],
            ),
          );
        addTearDown(registry.close);
        await expectLater(
          engine().executeWithRegistry(
            automation: automationFixture(
              nodes: [
                actionFixture('fail', action: 'fail'),
                actionFixture('later'),
              ],
              connections: [controlFixture('next', 'fail', 'later')],
              entryNodeId: 'fail',
            ),
            context: EvaluationContext(),
            registry: registry,
          ),
          throwsStateError,
        );
        expect(invoked, 0);
      },
    );
  }
}
