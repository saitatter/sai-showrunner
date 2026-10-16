import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sai_nodes/sai_nodes.dart' hide GraphNode;
import 'package:showrunner_flutter/plugins/overlays/shader_graph/shader_graph_compiler.dart';
import 'package:showrunner_flutter/plugins/overlays/shader_graph/shader_graph_editor.dart';
import 'package:showrunner_flutter/plugins/overlays/shader_graph/shader_graph_model.dart';

void main() {
  testWidgets(
    'starter switching, clipboard, reset and cancel keep graphs valid',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          if (call.method == 'Clipboard.getData') return {'text': clipboard};
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      ShaderGraphEditorResult? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showDialog<ShaderGraphEditorResult>(
                    context: context,
                    builder: (_) => const ShaderGraphEditorDialog(config: {}),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final controller = tester
          .widget<NodeEditorWidget>(find.byType(NodeEditorWidget))
          .controller;
      for (final starter in shaderGraphStarters) {
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text(starter.name).last);
        await tester.pumpAndSettle();
        expect(
          controller.nodes.length,
          createShaderGraphStarter(starter.id).nodes.length,
        );
        expect(controller.history.canUndo, false);
        await tester.tap(find.text('Compile & apply'));
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(FilledButton, 'Apply'),
          findsOneWidget,
          reason: starter.id,
        );
      }
      await tester.tap(find.byTooltip('Reset graph'));
      await tester.pumpAndSettle();
      final selection = controller.nodes.values
          .where((n) => {'uv', 'vec2_split'}.contains(n.prototype.idName))
          .map((n) => n.id)
          .toSet();
      controller.selectNodesById(selection);
      await tester.pumpAndSettle();
      await controller.clipboard.copySelection();
      expect(clipboard, isNotEmpty);
      await controller.clipboard.pasteSelection(position: const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(controller.nodes.length, 8);
      expect(controller.links.length, 6);
      expect(controller.nodes.keys.toSet().length, 8);
      final uv = controller.nodes.values.firstWhere(
        (n) => n.prototype.idName == 'uv',
      );
      final output = controller.nodes.values.singleWhere(
        (n) => n.prototype.idName == 'fragment_output',
      );
      expect(controller.addLink(uv.id, 'uv', output.id, 'alpha'), isNull);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compile & apply'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Apply'), findsOneWidget);
      controller.selectNodesById({output.id});
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete selection'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compile & apply'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Apply'), findsNothing);
      expect(find.textContaining('missing a Fragment Output'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(find.byType(ShaderGraphEditorDialog), findsNothing);
    },
  );
  testWidgets(
    'edits invalidate compilation and parameter bindings survive apply',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      ShaderGraphEditorResult? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showDialog<ShaderGraphEditorResult>(
                    context: context,
                    builder: (_) => const ShaderGraphEditorDialog(config: {}),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compile & apply'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Apply'), findsOneWidget);
      await tester.ensureVisible(
        find.widgetWithText(ListTile, 'Float Parameter'),
      );
      await tester.tap(find.widgetWithText(ListTile, 'Float Parameter'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Apply'), findsNothing);
      final controller = tester
          .widget<NodeEditorWidget>(find.byType(NodeEditorWidget))
          .controller;
      final parameter = controller.nodes.values.singleWhere(
        (n) => n.prototype.idName == 'uniform_float',
      );
      for (final entry in {
        'name': 'speed',
        'value': '0.25',
        'bindingSource': 'config',
        'bindingPath': 'customPulse',
      }.entries) {
        controller.setFieldData(
          parameter.id,
          entry.key,
          data: entry.value,
          eventType: FieldEventType.submit,
        );
      }
      final output = controller.nodes.values.singleWhere(
        (n) => n.prototype.idName == 'fragment_output',
      );
      expect(
        controller.addLink(parameter.id, 'value', output.id, 'alpha'),
        isNotNull,
      );
      controller.selectNodesById({parameter.id});
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add frame from selection'));
      await tester.pumpAndSettle();
      expect(find.text('Frame 1'), findsOneWidget);
      await tester.tap(find.byTooltip('Toggle node palette'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'Float Parameter'), findsNothing);
      await tester.tap(find.byTooltip('Toggle node palette'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compile & apply'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();
      expect(result!.uniforms['u_speed_custom'], 0.25);
      expect(result!.bindings['u_speed_custom'], {
        'source': 'config',
        'path': 'customPulse',
      });
      expect(result!.graph.frames.single.nodeIds, hasLength(1));
      expect(result!.glsl, compileShaderGraph(result!.graph).glsl);
    },
  );
  testWidgets(
    'opening and applying preserves shader node IDs, defaults and frame membership',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final base = createDefaultShaderGraph();
      final graph = base.copyWith(
        frames: [
          ShaderFrame(
            id: 'frame',
            title: 'Saved frame',
            color: '#7c4dff',
            x: 0,
            y: 0,
            width: 500,
            height: 300,
            nodeIds: base.nodes.map((n) => n.id).toList(),
          ),
        ],
      );
      ShaderGraphEditorResult? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showDialog<ShaderGraphEditorResult>(
                    context: context,
                    builder: (_) => ShaderGraphEditorDialog(
                      config: {'shaderGraph': graph.toJson()},
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final controller = tester
          .widget<NodeEditorWidget>(find.byType(NodeEditorWidget))
          .controller;
      expect(controller.history.canUndo, false);
      final positions = {
        for (final n in controller.nodes.values) n.id: n.offset,
      };
      await tester.tap(find.byTooltip('Auto layout'));
      await tester.pumpAndSettle();
      expect(controller.history.canUndo, true);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect({
        for (final n in controller.nodes.values) n.id: n.offset,
      }, positions);
      final accent = controller.nodes.values.singleWhere(
        (n) => n.prototype.idName == 'accent_color',
      );
      controller.selectNodesById({accent.id});
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete selection'));
      await tester.pumpAndSettle();
      expect(controller.nodes.length, 5);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(controller.nodes.length, 6);
      expect(controller.links.length, 5);
      await tester.tap(find.byTooltip('Redo'));
      await tester.pumpAndSettle();
      expect(controller.nodes.length, 5);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(controller.links.length, 5);
      await tester.tap(find.text('Compile & apply'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(FilledButton, 'Apply'),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data)
            .join(' | '),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(
        result!.graph.nodes.map((n) => n.id).toSet(),
        graph.nodes.map((n) => n.id).toSet(),
      );
      expect(
        result!.graph.frames.single.nodeIds.toSet(),
        result!.graph.nodes.map((n) => n.id).toSet(),
      );
      expect(compileShaderGraph(result!.graph).isValid, true);
    },
  );
}
