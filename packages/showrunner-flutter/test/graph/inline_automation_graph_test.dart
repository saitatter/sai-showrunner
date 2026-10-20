import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sai_nodes_core/sai_nodes_core.dart';
import 'package:showrunner_flutter/graph/domain/automation_document.dart';
import 'package:sai_nodes/sai_nodes.dart' show NodeEditor;
import 'package:showrunner_flutter/graph/controller/automation_editor_controller.dart';
import 'package:showrunner_flutter/graph/domain/automation_factories.dart';
import 'package:showrunner_flutter/graph/runtime/graph_execution_engine.dart';
import 'package:showrunner_flutter/graph/ui/graph_execution_trace_scope.dart';
import 'package:showrunner_flutter/graph/ui/inline_automation_graph.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/runtime/execution_trace.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/runtime/cancellation.dart';
import '../support/graph_fixtures.dart' show automationFixture, actionFixture;

void main() {
  testWidgets(
    'closing an inline editor cancels its running graph without dirtying it',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      DartCancellationToken? token;
      var stopped = false;
      final registry = DartPluginRegistry()
        ..register(
          DartPluginManifest(
            id: const PluginId('test'),
            name: 'Test',
            actions: [
              ActionSpec<RuntimeMap, Object?>(
                pluginId: const PluginId('test'),
                actionId: const ActionId('record'),
                invoke: (_, context) async {
                  token = context.cancellationToken;
                  await token!.whenCancelled;
                  stopped = true;
                  return null;
                },
              ),
            ],
          ),
        );
      final traces = ExecutionTraceService();
      final editor = AutomationEditorController(
        document: automationFixture(
          nodes: [actionFixture('a')],
          entryNodeId: 'a',
        ),
        registry: registry,
      );
      addTearDown(() async {
        editor.dispose();
        await registry.close();
        await traces.dispose();
      });
      final before = editor.document.graph;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GraphExecutionTraceScope(
              service: traces,
              engine: CompiledExecutionEngine(traceService: traces),
              child: InlineAutomationGraph(
                editor: editor,
                registryFuture: Future.value(registry),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Run'));
      await tester.pump();
      expect(token, isNotNull);
      expect(stopped, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(token!.isCancelled, isTrue);
      expect(stopped, isTrue);
      expect(editor.document.graph, same(before));
      expect(editor.isDirty, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'inline graphs show only their document traces and run through the application engine',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final service = ExecutionTraceService();
      final engine = CompiledExecutionEngine(traceService: service);
      final registry = DartPluginRegistry();
      final editor = AutomationEditorController(
        document: createSampleAutomation(),
        registry: registry,
      );
      addTearDown(() async {
        editor.dispose();
        await registry.close();
        await service.dispose();
      });
      final before = editor.document.graph;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GraphExecutionTraceScope(
              service: service,
              engine: engine,
              child: InlineAutomationGraph(
                editor: editor,
                registryFuture: Future.value(registry),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await engine.executeWithRegistry(
        automation: editor.document,
        registry: registry,
        context: EvaluationContext(),
        traceSource: const ExecutionTraceSource(
          type: 'profile',
          id: 'profile-file',
          subId: 'event-group',
        ),
      );
      // A different inline document can contain exactly the same authored node IDs.
      final other = AutomationDocument(
        graph: GraphDocument(id: 'other-inline', spaces: before.spaces),
        settings: editor.document.settings,
      );
      await engine.executeWithRegistry(
        automation: other,
        registry: registry,
        context: EvaluationContext(),
        traceSource: const ExecutionTraceSource(
          type: 'profile',
          id: 'profile-file',
          subId: 'another-event-group',
        ),
      );
      await tester.pump();
      final canvas = tester.widget<NodeEditor>(find.byType(NodeEditor));
      expect(canvas.executionSource!.snapshot.nodes, isNotEmpty);
      expect(find.text('Execution: '), findsOneWidget);
      final filteredRuns = service.snapshots.where(
        (run) => run.info.source.documentId == editor.document.id,
      );
      expect(filteredRuns, hasLength(1));
      expect(
        canvas.executionSource!.snapshot.executionId,
        filteredRuns.single.info.executionId,
      );
      expect(editor.document.graph, same(before));
      expect(editor.isDirty, false);
      await tester.tap(find.widgetWithText(TextButton, 'Run'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        service.snapshots.where(
          (run) => run.info.source.documentId == editor.document.id,
        ),
        hasLength(2),
      );
      expect(service.snapshots.last.info.mode, ExecutionTraceMode.test);
      expect(editor.document.graph, same(before));
      expect(editor.isDirty, false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test(
    'trace source filters treat absent sub-ID as a wildcard in the filter',
    () async {
      final service = ExecutionTraceService();
      addTearDown(service.dispose);
      final first = service.start(
        mode: ExecutionTraceMode.live,
        source: const ExecutionTraceSource(
          type: 'profile',
          id: 'p',
          subId: 'first',
          documentId: 'a',
        ),
      );
      final second = service.start(
        mode: ExecutionTraceMode.live,
        source: const ExecutionTraceSource(
          type: 'profile',
          id: 'p',
          subId: 'second',
          documentId: 'b',
        ),
      );
      expect(
        service.snapshotsFor(
          const ExecutionTraceSource(type: 'profile', id: 'p'),
        ),
        hasLength(2),
      );
      expect(
        service.activeFor(const ExecutionTraceSource(type: 'profile', id: 'p')),
        hasLength(2),
      );
      expect(
        service
            .snapshotsFor(
              const ExecutionTraceSource(
                type: 'profile',
                id: 'p',
                subId: 'first',
              ),
            )
            .single
            .info
            .executionId,
        first.executionId,
      );
      expect(
        service
            .snapshotsFor(
              const ExecutionTraceSource(
                type: 'profile',
                id: 'p',
                documentId: 'b',
              ),
            )
            .single
            .info
            .executionId,
        second.executionId,
      );
    },
  );
}
