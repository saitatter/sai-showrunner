import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sai_nodes_core/sai_nodes_core.dart';
import 'package:sai_nodes/sai_nodes.dart' show NodeEditor;
import 'package:showrunner_flutter/plugins/overlays/shader_graph/shader_graph_compiler.dart';
import 'package:showrunner_flutter/plugins/overlays/shader_graph/shader_graph_editor.dart';
import 'package:showrunner_flutter/plugins/overlays/shader_graph/shader_graph_model.dart';

Future<void> open(
  WidgetTester tester, {
  ShaderDocument? document,
  ValueChanged<ShaderGraphEditorResult?>? onResult,
}) async {
  await tester.binding.setSurfaceSize(const Size(1500, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            child: const Text('Open'),
            onPressed: () async {
              final result = await showDialog<ShaderGraphEditorResult>(
                context: context,
                builder: (_) => ShaderGraphEditorDialog(
                  config: {
                    if (document != null) 'shaderGraph': document.toJson(),
                  },
                ),
              );
              onResult?.call(result);
            },
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

GraphController controller(WidgetTester tester) =>
    tester.widget<NodeEditor>(find.byType(NodeEditor)).controller;
Future<void> click(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip(label));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets(
    'narrow shader editor exposes searchable creation and parameter inspector',
    (tester) async {
      await open(tester);
      await tester.binding.setSurfaceSize(const Size(560, 900));
      await tester.pumpAndSettle();
      await click(tester, 'Add shader node');
      await tester.enterText(
        find.widgetWithText(TextField, 'Search shader nodes'),
        'Float Parameter',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(ListTile, 'Float Parameter'));
      await tester.pumpAndSettle();
      final graph = controller(tester);
      final parameter = graph.activeSpace!.nodes.values.singleWhere(
        (node) => node.shaderDefinitionId == 'uniform_float',
      );
      expect(graph.selection.nodes, {parameter.id});
      await click(tester, 'Inspector');
      expect(find.byType(BottomSheet), findsOneWidget);
      final name = find.widgetWithText(TextField, 'Uniform name');
      await tester.ensureVisible(name);
      await tester.enterText(name, 'narrow');
      await tester.pump();
      expect(
        graph.activeSpace!.nodes[parameter.id]!.shaderValues['name'],
        'narrow',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'starter switching, clipboard, reset and cancel retain valid immutable graphs',
    (tester) async {
      ShaderGraphEditorResult? saved;
      await open(tester, onResult: (value) => saved = value);
      final graph = controller(tester);
      for (final starter in shaderGraphStarters) {
        await tester.tap(find.byType(DropdownButton<String>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text(starter.name).last);
        await tester.pumpAndSettle();
        expect(
          graph.activeSpace!.nodes.length,
          createShaderGraphStarter(starter.id).nodes.length,
        );
        expect(graph.canUndo, false);
        await tester.tap(find.text('Compile & apply'));
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(FilledButton, 'Apply'),
          findsOneWidget,
          reason: starter.id,
        );
      }
      await click(tester, 'Reset graph');
      graph.select(GraphSelection(nodes: {'uv', 'split_uv'}));
      final encoded = GraphFragment.capture(graph).encode();
      graph.pasteGraphFragment(GraphFragment.decode(encoded));
      await tester.pumpAndSettle();
      expect(graph.activeSpace!.nodes.length, 8);
      expect(graph.activeSpace!.connections.length, 6);
      final original = graph.document;
      expect(
        () => graph.execute(
          AddConnectionCommand(
            shaderSpaceId,
            createShaderConnection('bad', 'uv', 'uv', 'output', 'alpha'),
          ),
        ),
        throwsA(isA<GraphMutationException>()),
      );
      expect(graph.document, same(original));
      graph.select(GraphSelection(nodes: {'output'}));
      await tester.pump();
      await click(tester, 'Delete selection');
      await tester.tap(find.text('Compile & apply'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Apply'), findsNothing);
      expect(find.textContaining('missing a Fragment Output'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(find.byType(ShaderGraphEditorDialog), findsNothing);
    },
  );
  testWidgets('parameter fields, bindings and frame membership survive apply', (
    tester,
  ) async {
    ShaderGraphEditorResult? saved;
    await open(tester, onResult: (value) => saved = value);
    final graph = controller(tester);
    await tester.tap(find.text('Compile & apply'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Search shader nodes'),
      'Float Parameter',
    );
    await tester.pumpAndSettle();
    final parameterTile = find.widgetWithText(ListTile, 'Float Parameter');
    await tester.ensureVisible(parameterTile);
    await tester.tap(parameterTile);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Apply'), findsNothing);
    final parameter = graph.activeSpace!.nodes.values.singleWhere(
      (node) => node.shaderDefinitionId == 'uniform_float',
    );
    for (final entry in {
      'Uniform name': 'speed',
      'Value': '0.25',
      'Binding source (config/state)': 'config',
      'Binding path': 'customPulse',
    }.entries) {
      final field = find.widgetWithText(TextField, entry.key);
      await tester.ensureVisible(field);
      await tester.enterText(field, entry.value);
      await tester.pump();
    }
    graph.execute(
      AddConnectionCommand(
        shaderSpaceId,
        createShaderConnection(
          'alpha',
          parameter.id,
          'value',
          'output',
          'alpha',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await click(tester, 'Add frame from selection');
    expect(graph.activeSpace!.frames.values.single.memberNodeIds, {
      parameter.id,
    });
    await click(tester, 'Toggle node palette');
    expect(find.widgetWithText(ListTile, 'Float Parameter'), findsNothing);
    await click(tester, 'Toggle node palette');
    await tester.tap(find.text('Compile & apply'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();
    expect(saved!.uniforms['u_speed_custom'], .25);
    expect(saved!.bindings['u_speed_custom'], {
      'source': 'config',
      'path': 'customPulse',
    });
    expect(saved!.graph.space.frames.values.single.memberNodeIds, {
      parameter.id,
    });
    expect(saved!.glsl, compileShaderGraph(saved!.graph).glsl);
  });
  testWidgets(
    'layout, deletion undo and redo preserve actual IDs and saved geometry',
    (tester) async {
      final base = createDefaultShaderDocument();
      final frame = GraphFrame(
        id: 'frame',
        title: 'Saved frame',
        bounds: const GraphRect(0, 0, 1300, 650),
        memberNodeIds: base.space.nodes.keys.toSet(),
      );
      final document = ShaderDocument(
        base.graph.copyWith(
          spaces: {
            shaderSpaceId: base.space.copyWith(frames: {frame.id: frame}),
          },
        ),
      );
      ShaderGraphEditorResult? saved;
      await open(
        tester,
        document: document,
        onResult: (value) => saved = value,
      );
      final graph = controller(tester);
      final positions = graph.activeSpace!.nodePresentations;
      await click(tester, 'Auto layout');
      expect(graph.canUndo, true);
      await click(tester, 'Undo');
      expect(graph.activeSpace!.nodePresentations, positions);
      graph.select(GraphSelection(nodes: {'accent'}));
      await tester.pump();
      await click(tester, 'Delete selection');
      expect(graph.activeSpace!.nodes.length, 5);
      await click(tester, 'Undo');
      expect(graph.activeSpace!.nodes.length, 6);
      expect(graph.activeSpace!.connections.length, 5);
      await click(tester, 'Redo');
      expect(graph.activeSpace!.nodes.length, 5);
      await click(tester, 'Undo');
      await tester.tap(find.text('Compile & apply'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();
      expect(saved!.graph.graph, document.graph);
      expect(
        saved!.graph.space.nodes.keys.toSet(),
        base.space.nodes.keys.toSet(),
      );
      expect(
        saved!.graph.space.frames.values.single.memberNodeIds,
        base.space.nodes.keys.toSet(),
      );
    },
  );
}
