import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/graph/runtime/graph_execution_engine.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/runtime/action_queue.dart';
import 'package:showrunner_flutter/runtime/automation_queue_manager.dart';
import 'package:showrunner_flutter/runtime/automation_invocation_service.dart';
import 'package:showrunner_flutter/runtime/cancellation.dart';
import 'package:showrunner_flutter/runtime/execution_trace.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/runtime/graph_invocation.dart';
import '../support/graph_fixtures.dart';

void main() {
  late DartPluginRegistry registry;
  late DartActionQueue queue;
  late DartAutomationQueueManager queues;
  late AutomationInvocationService service;
  late ExecutionTraceService traces;
  final calls = <Object?>[];
  late AutomationDocument document;
  setUp(() {
    calls.clear();
    registry = DartPluginRegistry()
      ..register(
        DartPluginManifest(
          id: const PluginId('test'),
          name: 'Test',
          actions: [
            ActionSpec<RuntimeMap, Object?>(
              pluginId: const PluginId('test'),
              actionId: const ActionId('record'),
              invoke: (config, context) async {
                calls.add(context.contextState['event']);
                return {'done': true};
              },
            ),
          ],
        ),
      );
    addTearDown(registry.close);
    traces = ExecutionTraceService();
    addTearDown(traces.dispose);
    queue = DartActionQueue()..setPaused(true);
    queues = DartAutomationQueueManager(
      defaultQueue: queue,
      execute: (document, context, item) =>
          service.executeQueued(document, context, item),
    );
    addTearDown(queues.dispose);
    service = AutomationInvocationService(
      engine: CompiledExecutionEngine(traceService: traces),
      registry: () => registry,
      queues: queues,
    );
    document = automationFixture(nodes: [actionFixture('a')], entryNodeId: 'a');
  });

  GraphInvocation request({
    InvocationDispatch dispatch = InvocationDispatch.direct,
    InvocationContext? context,
    DartCancellationToken? cancellation,
  }) => GraphInvocation(
    target: InvocationDocument(document),
    origin: InvocationOrigin.chatCommand,
    sourceId: 'command',
    sourceSubId: 'entry',
    dispatch: dispatch,
    context: context,
    cancellation: cancellation,
  );

  test(
    'direct completion has actual results and stable source identity',
    () async {
      final result = await service.invokeOrThrow(request());
      expect(result, isA<InvocationCompleted>());
      expect((result as InvocationCompleted).execution.completed, isTrue);
      expect(result.completedAt.isBefore(result.startedAt), isFalse);
      expect(calls, hasLength(1));
      expect(queue.pending, isEmpty);
    },
  );

  test(
    'acceptance has a receipt and never fabricates graph completion',
    () async {
      final result = await service.invokeOrThrow(
        request(dispatch: InvocationDispatch.queued),
      );
      expect(result.status, InvocationStatus.accepted);
      expect(result, isNot(isA<InvocationCompleted>()));
      final receipt = (result as InvocationAccepted).receipt;
      expect(receipt.documentId, document.id);
      expect(receipt.queueId, 'default');
      expect(receipt.itemId, queue.pending.single.id);
      expect(calls, isEmpty);
      queue.setPaused(false);
      await queues.drain('default');
      expect(calls, hasLength(1));
      expect(queue.history.single.status, 'completed');
    },
  );

  test(
    'context collections are snapshotted and fresh for every evaluation',
    () {
      final values = <String, Object?>{
        'event': {'text': 'before'},
      };
      final snapshot = InvocationContext(state: values);
      (values['event'] as Map)['text'] = 'after';
      expect((snapshot.state['event'] as Map)['text'], 'before');
      expect(
        () => (snapshot.state['event'] as Map)['text'] = 'write',
        throwsUnsupportedError,
      );
      final first = snapshot.evaluate();
      (first.contextState['event'] as Map)['text'] = 'mutated';
      expect(
        (snapshot.evaluate().contextState['event'] as Map)['text'],
        'before',
      );
    },
  );

  test(
    'document queue dispatch preserves direct behavior without a queue ID',
    () async {
      final result = await service.invokeOrThrow(
        request(dispatch: InvocationDispatch.documentQueue),
      );
      expect(result, isA<InvocationCompleted>());
      expect(queue.pending, isEmpty);
    },
  );

  test(
    'missing documents have a load failure and original throwing identity',
    () async {
      final error = StateError('fixture load failed');
      final loader = AutomationInvocationService(
        engine: CompiledExecutionEngine(),
        registry: () => registry,
        loadDocument: (_) async => throw error,
      );
      final fileRequest = GraphInvocation(
        target: const InvocationFile('missing.yaml'),
        origin: InvocationOrigin.automation,
        sourceId: 'missing',
        dispatch: InvocationDispatch.direct,
      );
      final result = await loader.invoke(fileRequest) as InvocationFailed;
      expect(result.stage, InvocationFailureStage.load);
      expect(identical(result.error, error), isTrue);
      await expectLater(
        loader.invokeOrThrow(fileRequest),
        throwsA(same(error)),
      );
    },
  );

  test('pre-cancelled request never loads, enqueues or executes', () async {
    final token = DartCancellationToken()..cancel();
    final result = await service.invoke(
      request(dispatch: InvocationDispatch.queued, cancellation: token),
    );
    expect(result.status, InvocationStatus.cancelled);
    expect(queue.pending, isEmpty);
    expect(calls, isEmpty);
  });

  test(
    'invalid contracts are rejected before queue acceptance without mutation',
    () async {
      document = automationFixture(
        nodes: [actionFixture('missing', plugin: 'absent')],
        entryNodeId: 'missing',
      );
      final before = document.toJson();
      final result =
          await service.invoke(request(dispatch: InvocationDispatch.queued))
              as InvocationFailed;
      expect(result.stage, InvocationFailureStage.validation);
      expect(queue.pending, isEmpty);
      expect(document.toJson(), before);
    },
  );
}
