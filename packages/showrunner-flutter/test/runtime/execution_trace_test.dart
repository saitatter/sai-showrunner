import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/runtime/execution_trace.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/graph/runtime/production_graph_vm.dart';
import 'package:showrunner_flutter/graph/runtime/graph_runtime.dart';
import '../support/graph_fixtures.dart';

void main() {
  test('creates ordered bounded traces for concurrent runs', () async {
    final service = ExecutionTraceService(maxRuns: 4, maxEventsPerRun: 4);
    final source = const ExecutionTraceSource(type: 'automation', id: 'demo');
    final first = service.start(mode: ExecutionTraceMode.live, source: source);
    final second = service.start(mode: ExecutionTraceMode.live, source: source);

    first.nodeStarted(const ExecutionNodeRef(nodeId: 'action'));
    first.nodeResult(const ExecutionNodeRef(nodeId: 'action'), {
      'message': 'ok',
    });
    first.nodeCompleted(
      const ExecutionNodeRef(nodeId: 'action'),
      duration: const Duration(milliseconds: 12),
    );
    first.end(ExecutionTraceRunStatus.completed);
    second.nodeStarted(const ExecutionNodeRef(nodeId: 'action'));

    expect(first.executionId, isNot(second.executionId));
    expect(service.activeFor(source), hasLength(1));
    final firstSnapshot = service.snapshotFor(first.executionId)!;
    expect(firstSnapshot.info.status, ExecutionTraceRunStatus.completed);
    expect(firstSnapshot.events.length, lessThanOrEqualTo(4));
    expect(
      firstSnapshot.nodes[const ExecutionNodeRef(nodeId: 'action').key]?.status,
      ExecutionTraceNodeStatus.success,
    );

    await service.dispose();
  });

  test('sanitizes deeply nested and oversized results', () {
    final result = sanitizeExecutionResult({
      'deep': {
        'one': {
          'two': {
            'three': {
              'four': {
                'five': {'six': true},
              },
            },
          },
        },
      },
      'large': List.filled(100, 'x'),
    });

    expect(result.truncated, isTrue);
    expect(result.value, isA<Map>());
  });

  test('closes active nodes as aborted when a run ends', () async {
    final service = ExecutionTraceService();
    final session = service.start(
      mode: ExecutionTraceMode.live,
      source: const ExecutionTraceSource(type: 'automation', id: 'abort'),
    );
    const node = ExecutionNodeRef(nodeId: 'wait');
    session.nodeStarted(node);
    session.end(ExecutionTraceRunStatus.aborted);

    final snapshot = service.snapshotFor(session.executionId)!;
    expect(snapshot.info.status, ExecutionTraceRunStatus.aborted);
    expect(
      snapshot.nodes[const ExecutionNodeRef(nodeId: 'wait').key]?.status,
      ExecutionTraceNodeStatus.aborted,
    );

    await service.dispose();
  });

  test(
    'production VM emits action events and callbacks without changing results',
    () async {
      final callbacks = <String>[];
      final traced = await trace(
        automationFixture(
          nodes: [
            actionFixture('action', config: {'value': 42}),
          ],
          entryNodeId: 'action',
        ),
        callbacks: callbacks,
      );
      expect(traced.result!.completed, true);
      expect(traced.result!.nodeResults['action']!['value'], 42);
      expect(callbacks, ['enter:action', 'exit:action']);
      expect(traced.snapshot.events.map((event) => event.type), [
        'run.started',
        'node.started',
        'node.result',
        'node.completed',
        'run.ended',
      ]);
      expect(
        traced.snapshot.events
            .whereType<ExecutionNodeCompletedEvent>()
            .single
            .duration,
        isA<Duration>(),
      );
    },
  );
  test('failed action emits bounded error and terminal status', () async {
    final traced = await trace(
      automationFixture(
        nodes: [actionFixture('action')],
        entryNodeId: 'action',
      ),
      action: (node, config, context) async =>
          throw StateError('expected failure'),
    );
    expect(traced.error, isA<StateError>());
    expect(traced.snapshot.info.status, ExecutionTraceRunStatus.error);
    final state =
        traced.snapshot.nodes[const ExecutionNodeRef(nodeId: 'action').key]!;
    expect(state.status, ExecutionTraceNodeStatus.error);
    expect(state.error!.message, contains('expected failure'));
  });
  test(
    'actual trigger and unified control connection IDs appear directly in traces',
    () async {
      final document = eventFixture(
        id: 'trigger',
        nodes: [actionFixture('first'), actionFixture('second')],
        next: 'first',
        connections: [controlFixture('first-second', 'first', 'second')],
      );
      final traced = await trace(document);
      final edges = traced.snapshot.events
          .whereType<ExecutionEdgeTraversedEvent>()
          .map((event) => event.edge)
          .toList();
      expect(edges.map((edge) => edge.edgeId), [
        'trigger:next',
        'first-second',
      ]);
      expect(edges.first.from.nodeId, 'trigger');
      expect(edges.first.to.nodeId, 'first');
      expect(edges.last.to.nodeId, 'second');
    },
  );
  test(
    'control-flow trace records selected branch and control lifecycle',
    () async {
      final traced = await trace(
        automationFixture(
          nodes: [
            GraphNode(
              id: 'branch',
              type: 'showrunner.if',
              data: {'condition': true},
            ),
            actionFixture('trueAction'),
            actionFixture('falseAction'),
          ],
          entryNodeId: 'branch',
          connections: [
            controlFixture(
              'true-edge',
              'branch',
              'trueAction',
              port: 'flow:then',
            ),
            controlFixture(
              'false-edge',
              'branch',
              'falseAction',
              port: 'flow:else',
            ),
          ],
        ),
      );
      final branch =
          traced.snapshot.nodes[const ExecutionNodeRef(nodeId: 'branch').key]!;
      expect(branch.selectedPort, 'then');
      expect(branch.status, ExecutionTraceNodeStatus.success);
      expect(
        traced.snapshot.nodes[const ExecutionNodeRef(
          nodeId: 'falseAction',
        ).key],
        isNull,
      );
      expect(
        traced
            .snapshot
            .nodes[const ExecutionNodeRef(nodeId: 'trueAction').key]!
            .status,
        ExecutionTraceNodeStatus.success,
      );
    },
  );
  for (final direct in [false, true]) {
    test(
      'subgraph trace retains exact scope for ${direct ? 'direct node execution' : 'nested calls'}',
      () async {
        final signature = AutomationSubgraph(
          id: 'inner',
          name: 'Inner',
          entryNodeId: 'innerAction',
        );
        final document = automationFixture(
          nodes: [
            GraphNode(
              id: 'call',
              type: 'showrunner.subgraphCall',
              data: {'subgraphId': signature.id},
            ),
          ],
          entryNodeId: 'call',
          subgraphs: {signature.id: signature},
          spaces: {
            signature.spaceId: GraphSpace(
              id: signature.spaceId,
              nodes: {'innerAction': actionFixture('innerAction')},
            ),
          },
        );
        final traced = await trace(
          document,
          spaceId: direct ? signature.spaceId : mainAutomationSpace,
        );
        expect(traced.error, isNull);
        expect(
          traced.snapshot.events.whereType<ExecutionSubgraphEnteredEvent>(),
          hasLength(direct ? 0 : 1),
        );
        expect(
          traced.snapshot.events.whereType<ExecutionSubgraphExitedEvent>(),
          hasLength(direct ? 0 : 1),
        );
        expect(
          traced
              .snapshot
              .nodes[const ExecutionNodeRef(
                nodeId: 'innerAction',
                scope: SubgraphScope('inner'),
              ).key]!
              .status,
          ExecutionTraceNodeStatus.success,
        );
        expect(
          traced.snapshot.nodes[const ExecutionNodeRef(
            nodeId: 'innerAction',
          ).key],
          isNull,
        );
        if (!direct) {
          expect(
            traced
                .snapshot
                .nodes[const ExecutionNodeRef(nodeId: 'call').key]!
                .status,
            ExecutionTraceNodeStatus.success,
          );
        }
      },
    );
  }
  for (final count in [0, 3]) {
    test('loop trace records exactly $count executed iterations', () async {
      final traced = await trace(
        automationFixture(
          nodes: [
            GraphNode(
              id: 'for',
              type: 'showrunner.for',
              data: {'start': 0, 'end': count, 'step': 1},
            ),
            actionFixture('body'),
            GraphNode(id: 'done', type: 'showrunner.return'),
          ],
          entryNodeId: 'for',
          connections: [
            controlFixture('body-edge', 'for', 'body', port: 'flow:body'),
            controlFixture('next-edge', 'for', 'done', port: 'flow:next'),
          ],
        ),
      );
      expect(traced.error, isNull);
      expect(
        traced.snapshot.events.whereType<ExecutionLoopIterationEvent>().map(
          (event) => event.iteration,
        ),
        List.generate(count, (index) => index + 1),
      );
      expect(
        traced
            .snapshot
            .nodes[const ExecutionNodeRef(nodeId: 'for').key]!
            .status,
        ExecutionTraceNodeStatus.success,
      );
      expect(
        traced
            .snapshot
            .nodes[const ExecutionNodeRef(nodeId: 'done').key]!
            .status,
        ExecutionTraceNodeStatus.success,
      );
    });
  }
}

Future<
  ({
    GraphExecutionResult? result,
    ExecutionTraceRunSnapshot snapshot,
    Object? error,
  })
>
trace(
  AutomationDocument document, {
  DartProgramAction? action,
  List<String>? callbacks,
  String spaceId = mainAutomationSpace,
}) async {
  final service = ExecutionTraceService();
  final session = service.start(
    mode: ExecutionTraceMode.test,
    source: ExecutionTraceSource(type: 'automation', id: document.id),
  );
  GraphExecutionResult? result;
  Object? failure;
  try {
    final program = DartProductionGraphCompiler().compileAutomation(
      document,
      entrySpaceId: spaceId,
    );
    result =
        await DartGraphVm(
          program,
          traceSink: session,
          onNodeEnter: (id) => callbacks?.add('enter:$id'),
          onNodeExit: (id) => callbacks?.add('exit:$id'),
        ).execute(
          context: EvaluationContext(),
          action:
              action ??
              (node, config, context) async => {'value': config['value']},
        );
    session.end(ExecutionTraceRunStatus.completed);
  } catch (error, stack) {
    failure = error;
    session.end(ExecutionTraceRunStatus.error, error: error, stackTrace: stack);
  }
  final snapshot = service.snapshotFor(session.executionId)!;
  await service.dispose();
  return (result: result, snapshot: snapshot, error: failure);
}
