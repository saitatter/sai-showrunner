import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/runtime/execution_trace.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/runtime/production_graph_vm.dart';
import 'package:showrunner_flutter/schema/automation.dart';

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
      firstSnapshot.nodes['main:action']?.status,
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
      snapshot.nodes['main:wait']?.status,
      ExecutionTraceNodeStatus.aborted,
    );

    await service.dispose();
  });

  test(
    'production VM emits action trace events without changing results',
    () async {
      const automation = AutomationData(
        graph: AutomationGraph(
          entryNodeId: 'action',
          nodes: [
            GraphNode(
              id: 'action',
              type: 'action',
              x: 0,
              y: 0,
              data: {
                'config': {'value': 42},
              },
            ),
          ],
        ),
      );
      final program = DartProductionGraphCompiler().compileAutomation(
        automation,
      );
      final service = ExecutionTraceService();
      final session = service.start(
        mode: ExecutionTraceMode.test,
        source: const ExecutionTraceSource(type: 'automation', id: 'demo'),
      );

      final result = await DartGraphVm(program, traceSink: session).execute(
        context: EvaluationContext(),
        action: (node, config, context) async => {'value': config['value']},
      );
      session.end(ExecutionTraceRunStatus.completed);

      final events = service.snapshotFor(session.executionId)!.events;
      expect(result.completed, isTrue);
      expect(events.map((event) => event.type), [
        'run.started',
        'node.started',
        'node.result',
        'node.completed',
        'run.ended',
      ]);
      expect(
        (events.whereType<ExecutionNodeCompletedEvent>().single).duration,
        isA<Duration>(),
      );

      await service.dispose();
    },
  );

  test('failed action emits a bounded error and terminal run status', () async {
    const automation = AutomationData(
      graph: AutomationGraph(
        entryNodeId: 'action',
        nodes: [GraphNode(id: 'action', type: 'action', x: 0, y: 0)],
      ),
    );
    final program = DartProductionGraphCompiler().compileAutomation(automation);
    final service = ExecutionTraceService();
    final session = service.start(
      mode: ExecutionTraceMode.live,
      source: const ExecutionTraceSource(type: 'automation', id: 'failure'),
    );

    await expectLater(
      DartGraphVm(program, traceSink: session).execute(
        context: EvaluationContext(),
        action: (node, config, context) async {
          throw StateError('expected failure');
        },
      ),
      throwsA(isA<StateError>()),
    );
    session.end(
      ExecutionTraceRunStatus.error,
      error: StateError('expected failure'),
    );

    final snapshot = service.snapshotFor(session.executionId)!;
    expect(snapshot.info.status, ExecutionTraceRunStatus.error);
    expect(
      snapshot.nodes['main:action']?.status,
      ExecutionTraceNodeStatus.error,
    );
    expect(
      snapshot.nodes['main:action']?.error?.message,
      contains('expected failure'),
    );

    await service.dispose();
  });

  test('production VM emits exact flow edges with their ports', () async {
    const automation = AutomationData(
      graph: AutomationGraph(
        entryNodeId: 'trigger',
        nodes: [
          GraphNode(id: 'first', type: 'action', x: 0, y: 0),
          GraphNode(id: 'second', type: 'action', x: 120, y: 0),
        ],
        edges: [
          GraphEdge(id: 'trigger-first', from: 'trigger', to: 'first'),
          GraphEdge(
            id: 'first-second',
            from: 'first',
            to: 'second',
            port: 'completed',
          ),
        ],
      ),
    );
    final program = DartProductionGraphCompiler().compileAutomation(automation);
    final service = ExecutionTraceService();
    final session = service.start(
      mode: ExecutionTraceMode.test,
      source: const ExecutionTraceSource(type: 'automation', id: 'edges'),
    );

    await DartGraphVm(program, traceSink: session).execute(
      context: EvaluationContext(),
      action: (node, config, context) async => null,
    );
    session.end(ExecutionTraceRunStatus.completed);

    final edges = service
        .snapshotFor(session.executionId)!
        .events
        .whereType<ExecutionEdgeTraversedEvent>()
        .toList();
    expect(edges, hasLength(2));
    expect(edges[0].edge.edgeId, 'trigger-first');
    expect(edges[0].edge.from.nodeId, 'trigger');
    expect(edges[0].edge.to.nodeId, 'first');
    expect(edges[1].edge.edgeId, 'first-second');
    expect(edges[1].edge.port, 'completed');

    await service.dispose();
  });

  test(
    'control-flow trace records the selected branch and control lifecycle',
    () async {
      const automation = AutomationData(
        graph: AutomationGraph(
          entryNodeId: 'branch',
          nodes: [
            GraphNode(
              id: 'branch',
              type: 'if',
              x: 0,
              y: 0,
              data: {
                'condition': {'type': 'literal', 'value': true},
              },
            ),
            GraphNode(id: 'trueAction', type: 'action', x: 120, y: -40),
            GraphNode(id: 'falseAction', type: 'action', x: 120, y: 40),
          ],
          edges: [
            GraphEdge(
              id: 'branch-then',
              from: 'branch',
              to: 'trueAction',
              port: 'then',
            ),
            GraphEdge(
              id: 'branch-else',
              from: 'branch',
              to: 'falseAction',
              port: 'else',
            ),
          ],
        ),
      );
      final service = ExecutionTraceService();
      final session = service.start(
        mode: ExecutionTraceMode.test,
        source: const ExecutionTraceSource(type: 'automation', id: 'branch'),
      );
      final program = DartProductionGraphCompiler().compileAutomation(
        automation,
      );

      await DartGraphVm(program, traceSink: session).execute(
        context: EvaluationContext(),
        action: (node, config, context) async => null,
      );
      session.end(ExecutionTraceRunStatus.completed);

      final snapshot = service.snapshotFor(session.executionId)!;
      final path = snapshot.events
          .whereType<ExecutionControlPathEvent>()
          .single;
      expect(path.node.nodeId, 'branch');
      expect(path.port, 'then');
      expect(
        snapshot.nodes['main:branch']?.status,
        ExecutionTraceNodeStatus.success,
      );
      expect(snapshot.nodes['main:branch']?.selectedPort, 'then');
      expect(snapshot.nodes['main:falseAction'], isNull);
      expect(
        snapshot.nodes['main:trueAction']?.status,
        ExecutionTraceNodeStatus.success,
      );

      await service.dispose();
    },
  );

  test('subgraph trace exposes parent call and nested graph scope', () async {
    const automation = AutomationData(
      graph: AutomationGraph(
        entryNodeId: 'call',
        nodes: [
          GraphNode(
            id: 'call',
            type: 'subgraphCall',
            x: 0,
            y: 0,
            data: {'subgraphId': 'inner'},
          ),
        ],
      ),
      subgraphs: [
        SubgraphDefinition(
          id: 'inner',
          name: 'Inner',
          entryNodeId: 'innerAction',
          nodes: [GraphNode(id: 'innerAction', type: 'action', x: 0, y: 0)],
          edges: [],
        ),
      ],
    );
    final service = ExecutionTraceService();
    final session = service.start(
      mode: ExecutionTraceMode.test,
      source: const ExecutionTraceSource(type: 'automation', id: 'subgraph'),
    );
    final program = DartProductionGraphCompiler().compileAutomation(automation);

    await DartGraphVm(program, traceSink: session).execute(
      context: EvaluationContext(),
      action: (node, config, context) async => {'done': true},
    );
    session.end(ExecutionTraceRunStatus.completed);

    final snapshot = service.snapshotFor(session.executionId)!;
    expect(
      snapshot.events.whereType<ExecutionSubgraphEnteredEvent>(),
      hasLength(1),
    );
    expect(
      snapshot.events.whereType<ExecutionSubgraphExitedEvent>(),
      hasLength(1),
    );
    expect(
      snapshot.nodes['main:call']?.status,
      ExecutionTraceNodeStatus.success,
    );
    expect(
      snapshot.nodes['inner:innerAction']?.status,
      ExecutionTraceNodeStatus.success,
    );

    await service.dispose();
  });

  test(
    'production VM traces loop iterations and zero-iteration completion',
    () async {
      const automation = AutomationData(
        graph: AutomationGraph(
          entryNodeId: 'for',
          nodes: [
            GraphNode(
              id: 'for',
              type: 'for',
              x: 0,
              y: 0,
              data: {
                'variable': 'index',
                'start': {'type': 'literal', 'value': 0},
                'end': {'type': 'literal', 'value': 3},
                'step': {'type': 'literal', 'value': 1},
              },
            ),
            GraphNode(id: 'body', type: 'action', x: 120, y: 0),
            GraphNode(id: 'done', type: 'return', x: 240, y: 0),
          ],
          edges: [
            GraphEdge(id: 'body-edge', from: 'for', to: 'body', port: 'body'),
            GraphEdge(id: 'repeat', from: 'body', to: 'for'),
            GraphEdge(id: 'next', from: 'for', to: 'done', port: 'next'),
          ],
        ),
      );
      final service = ExecutionTraceService();
      final session = service.start(
        mode: ExecutionTraceMode.test,
        source: const ExecutionTraceSource(type: 'automation', id: 'loop'),
      );

      final program = DartProductionGraphCompiler().compileAutomation(
        automation,
      );
      await DartGraphVm(program, traceSink: session).execute(
        context: EvaluationContext(),
        action: (node, config, context) async => null,
      );
      session.end(ExecutionTraceRunStatus.completed);

      final snapshot = service.snapshotFor(session.executionId)!;
      expect(
        snapshot.events.whereType<ExecutionLoopIterationEvent>().map(
          (event) => event.iteration,
        ),
        [1, 2, 3],
      );
      expect(snapshot.nodes['main:for']?.lastIteration, 3);
      expect(
        snapshot.nodes['main:for']?.status,
        ExecutionTraceNodeStatus.success,
      );
      expect(
        snapshot.nodes['main:done']?.status,
        ExecutionTraceNodeStatus.success,
      );

      await service.dispose();
    },
  );
}
