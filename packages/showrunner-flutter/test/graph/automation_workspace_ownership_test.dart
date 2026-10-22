import 'dart:async';
import 'package:sai_nodes_core/sai_nodes_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/graph/controller/automation_editor_controller.dart';
import 'package:showrunner_flutter/graph/domain/automation_document.dart';
import 'package:showrunner_flutter/graph/execution/showrunner_execution_visual_adapter.dart';
import 'package:showrunner_flutter/graph/ui/automation_graph_workspace.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/runtime/execution_trace.dart';

void main() {
  late DartPluginRegistry registry;
  late AutomationEditorController first, second;
  setUp(() {
    registry = DartPluginRegistry();
    first = AutomationEditorController(
      document: AutomationDocument.empty(id: 'first'),
      registry: registry,
    );
    second = AutomationEditorController(
      document: AutomationDocument.empty(id: 'second'),
      registry: registry,
    );
  });
  tearDown(() async {
    first.dispose();
    second.dispose();
    await registry.close();
  });
  Widget app(
    AutomationEditorController editor, {
    ShowrunnerExecutionVisualAdapter? execution,
    Future<void> Function(AutomationDocument)? onRun,
  }) => MaterialApp(
    home: Scaffold(
      body: AutomationGraphWorkspace(
        editor: editor,
        execution: execution,
        onRun: onRun,
      ),
    ),
  );
  testWidgets(
    'diagnostics opened for an old document cannot select in its replacement',
    (tester) async {
      first.graph.execute(
        AddNodeCommand(
          first.graph.activeSpaceId!,
          GraphNode(id: 'unavailable', type: 'missing.type'),
        ),
      );
      second.graph.execute(
        AddNodeCommand(
          second.graph.activeSpaceId!,
          GraphNode(id: 'unavailable', type: 'missing.type'),
        ),
      );
      await tester.pumpWidget(app(first));
      await tester.tap(find.textContaining('graph issue(s)'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(app(second));
      await tester.pump();
      await tester.tap(
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(ListTile),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(second.graph.selection.nodes, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'node picker opened for a replaced document cannot insert into its replacement',
    (tester) async {
      await tester.pumpWidget(app(first));
      await tester.tap(find.byKey(const ValueKey('graph-add-node')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(app(second));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Search nodes'),
        'If',
      );
      await tester.pump();
      final choice = find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(ListTile),
          )
          .first;
      await tester.tap(choice);
      await tester.pumpAndSettle();
      expect(second.graph.activeSpace!.nodes, isEmpty);
      expect(first.graph.activeSpace!.nodes, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('trace updates do not rebuild workspace authoring controls', (
    tester,
  ) async {
    final service = ExecutionTraceService();
    const source = ExecutionTraceSource(type: 'automation', id: 'first');
    final adapter = ShowrunnerExecutionVisualAdapter(
      service: service,
      source: source,
    );
    addTearDown(() async {
      adapter.dispose();
      await service.dispose();
    });
    var builds = 0;
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previous?.call(element, builtOnce);
      if (element.widget is AutomationGraphWorkspace) builds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previous);
    await tester.pumpWidget(app(first, execution: adapter));
    await tester.pumpAndSettle();
    final baseline = builds;
    final revision = first.graph.revision;
    service.start(mode: ExecutionTraceMode.test, source: source);
    await tester.pump();
    await tester.pump();
    expect(find.text('Execution: '), findsOneWidget);
    expect(builds, baseline);
    expect(first.graph.revision, revision);
    expect(first.isDirty, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('replacing an editor dismisses its compact inspector sheet', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(560, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(first));
    await tester.tap(find.byTooltip('Inspector'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.pumpWidget(app(second));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'a parameter form cannot overwrite a changed subgraph signature',
    (tester) async {
      final id = first.createSubgraph();
      await tester.pumpWidget(app(first));
      await tester.tap(find.text('Add parameter'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Name'),
        'Old form',
      );
      final original = first.document.subgraphs[id]!;
      first.updateSubgraph(original.copyWith(name: 'Changed elsewhere'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(first.document.subgraphs[id]!.name, 'Changed elsewhere');
      expect(first.document.subgraphs[id]!.parameters, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('an old run completion cannot clear a replacement editor run', (
    tester,
  ) async {
    final oldRun = Completer<void>();
    final newRun = Completer<void>();
    await tester.pumpWidget(app(first, onRun: (_) => oldRun.future));
    await tester.tap(find.widgetWithText(TextButton, 'Run'));
    await tester.pump();
    await tester.pumpWidget(app(second, onRun: (_) => newRun.future));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Run'));
    await tester.pump();
    oldRun.completeError(StateError('private-provider-payload'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Run'))
          .onPressed,
      isNull,
    );
    expect(find.textContaining('private-provider-payload'), findsNothing);
    newRun.complete();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Run'))
          .onPressed,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final size in const [
    Size(1024, 640),
    Size(1280, 720),
    Size(1440, 900),
    Size(1920, 1080),
  ]) {
    for (final dpr in [1.0, 1.5]) {
      testWidgets(
        'graph controls fit $size at DPR $dpr with long subgraph names',
        (tester) async {
          tester.view.physicalSize = size * dpr;
          tester.view.devicePixelRatio = dpr;
          addTearDown(tester.view.reset);
          final id = first.createSubgraph();
          first.updateSubgraph(
            first.document.subgraphs[id]!.copyWith(
              name: List.filled(20, 'Long subgraph').join(' '),
            ),
          );
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  devicePixelRatio: dpr,
                  textScaler: TextScaler.linear(1.5),
                ),
                child: Scaffold(
                  body: Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: size.width - 300,
                      child: AutomationGraphWorkspace(editor: first),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byKey(const ValueKey('graph-add-node')), findsOneWidget);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
