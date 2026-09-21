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
}
