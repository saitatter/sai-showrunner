import 'package:flutter_test/flutter_test.dart';
import 'package:sai_nodes_core/sai_nodes_core.dart';
import 'package:showrunner_flutter/graph/domain/automation_document.dart';
import 'package:showrunner_flutter/graph/execution/showrunner_execution_visual_adapter.dart';
import 'package:showrunner_flutter/runtime/execution_trace.dart';

void main() {
  test(
    'concurrent and pinned runs retain exact counts beyond bounded event history',
    () async {
      final service = ExecutionTraceService(maxEventsPerRun: 2);
      const source = ExecutionTraceSource(type: 'automation', id: 'd');
      final adapter = ShowrunnerExecutionVisualAdapter(
        service: service,
        source: source,
      );
      addTearDown(() async {
        adapter.dispose();
        await service.dispose();
      });
      final first = service.start(
        mode: ExecutionTraceMode.live,
        source: source,
      );
      final second = service.start(
        mode: ExecutionTraceMode.live,
        source: source,
      );
      const node = ExecutionNodeRef(nodeId: 'stable');
      const from = ExecutionNodeRef(nodeId: 'source');
      const key = ScopedNodeRef(mainAutomationSpace, 'stable');
      const edgeKey = ScopedConnectionRef(mainAutomationSpace, 'edge');
      for (var i = 0; i < 10; i++) {
        first.edgeTraversed(
          const ExecutionEdgeRef(edgeId: 'edge', from: from, to: node),
        );
      }
      first.nodeStarted(node, invocation: 1);
      first.nodeStarted(node, invocation: 2);
      second.nodeStarted(node, invocation: 1);
      await Future<void>.delayed(Duration.zero);
      expect(adapter.snapshot.nodes[key]!.activeCount, 3);
      expect(adapter.snapshot.nodes[key]!.invocationCount, 3);
      expect(adapter.snapshot.connections[edgeKey]!.traversalCount, 10);
      expect(adapter.snapshot.connections[edgeKey]!.active, true);
      first.nodeCompleted(
        node,
        invocation: 2,
        duration: const Duration(milliseconds: 12),
      );
      await Future<void>.delayed(Duration.zero);
      expect(adapter.snapshot.nodes[key]!.activeCount, 2);
      adapter.pin(first.executionId);
      expect(adapter.snapshot.nodes[key]!.activeCount, 1);
      expect(adapter.snapshot.nodes[key]!.invocationCount, 2);
      first.end(ExecutionTraceRunStatus.aborted);
      await Future<void>.delayed(Duration.zero);
      expect(adapter.snapshot.nodes[key]!.status, GraphExecutionStatus.aborted);
      expect(adapter.snapshot.nodes[key]!.activeCount, 0);
      expect(adapter.snapshot.connections[edgeKey]!.active, false);
      adapter.pin(null);
      expect(adapter.snapshot.executionId, second.executionId);
      second.nodeCompleted(node, invocation: 1);
      second.end(ExecutionTraceRunStatus.completed);
      await Future<void>.delayed(Duration.zero);
      expect(
        adapter.snapshot.nodes[key]!.status,
        GraphExecutionStatus.completed,
      );
      adapter.pin('missing');
      expect(adapter.snapshot.nodes, isEmpty);
    },
  );
  test(
    'main and named subgraph scopes never collide; loop metadata survives retention',
    () async {
      final service = ExecutionTraceService(maxEventsPerRun: 1);
      const source = ExecutionTraceSource(type: 'automation', id: 'd');
      final adapter = ShowrunnerExecutionVisualAdapter(
        service: service,
        source: source,
      );
      addTearDown(() async {
        adapter.dispose();
        await service.dispose();
      });
      final run = service.start(mode: ExecutionTraceMode.test, source: source);
      const main = ExecutionNodeRef(nodeId: 'same');
      const nested = ExecutionNodeRef(
        nodeId: 'same',
        scope: SubgraphScope('main'),
      );
      expect(main.key, isNot(nested.key));
      run.nodeStarted(main);
      run.nodeStarted(nested);
      run.loopIteration(nested, 9);
      run.nodeCompleted(
        nested,
        invocation: 1,
        duration: const Duration(milliseconds: 3),
      );
      run.nodeCompleted(main, invocation: 1);
      run.end(ExecutionTraceRunStatus.completed);
      await Future<void>.delayed(Duration.zero);
      expect(adapter.snapshot.nodes, hasLength(2));
      final visual = adapter
          .snapshot
          .nodes[const ScopedNodeRef('space:subgraph:main', 'same')]!;
      expect(visual.metadata['lastIteration'], 9);
      expect(visual.duration, const Duration(milliseconds: 3));
      expect(visual.status, GraphExecutionStatus.completed);
      adapter.setSource(
        const ExecutionTraceSource(type: 'automation', id: 'other'),
      );
      expect(adapter.snapshot.nodes, isEmpty);
    },
  );
}
