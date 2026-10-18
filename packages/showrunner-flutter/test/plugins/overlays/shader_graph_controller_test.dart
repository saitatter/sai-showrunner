import 'package:flutter_test/flutter_test.dart';
import 'package:sai_nodes/sai_nodes.dart';
import 'package:showrunner_flutter/plugins/overlays/shader_graph/shader_graph_controller.dart';
import 'package:showrunner_flutter/plugins/overlays/shader_graph/shader_graph_compiler.dart';
import 'package:showrunner_flutter/plugins/overlays/shader_graph/shader_graph_model.dart';
import 'package:showrunner_flutter/plugins/overlays/shader_graph/shader_node_definitions.dart';

void main() {
  test('shader starters leave visible space between resolved node bounds', () {
    for (final document in [
      createDefaultShaderDocument(),
      ...shaderGraphStarters.map(
        (starter) => createShaderGraphStarter(starter.id),
      ),
    ]) {
      final editor = ShaderEditorController(document);
      addTearDown(editor.dispose);
      final nodes = GraphSceneBuilder()
          .build(editor.graph)
          .nodes
          .values
          .toList();
      for (var i = 0; i < nodes.length; i++) {
        for (var j = i + 1; j < nodes.length; j++) {
          expect(
            nodes[i].geometry.bounds
                .inflate(8)
                .overlaps(nodes[j].geometry.bounds),
            false,
            reason: '${nodes[i].node.id} overlaps ${nodes[j].node.id}',
          );
        }
      }
    }
  });
  test(
    'every shader node resolves exact typed ports and all editable defaults',
    () {
      final document = createShaderDocument(
        nodes: [
          for (final definition in shaderNodeDefinitions)
            createShaderNode(definition.id, definition.id),
        ],
      );
      final editor = ShaderEditorController(document);
      addTearDown(editor.dispose);
      expect(editor.graph.resolution.diagnostics, isEmpty);
      for (final definition in shaderNodeDefinitions) {
        final structure =
            editor.graph.resolution.structures[shaderSpaceId]![definition.id]!;
        expect(
          structure.ports.length,
          definition.inputs.length + definition.outputs.length,
        );
        for (final port in definition.inputs) {
          final resolved = structure.ports.singleWhere(
            (item) => item.id == 'in:${port.key}',
          );
          expect(resolved.dataType, 'shader.${port.type.glsl}');
          expect(resolved.maxConnections, 1);
        }
        expect(
          structure.fields.map((field) => field.id),
          shaderFields(definition).map((field) => field.id),
        );
      }
    },
  );
  test(
    'layout and selection reuse GLSL; semantic edits and undo invalidate compilation',
    () {
      final editor = ShaderEditorController(createDefaultShaderDocument());
      addTearDown(editor.dispose);
      final first = editor.compile();
      editor.graph.execute(
        MoveNodesCommand(shaderSpaceId, {'uv': const GraphPoint(900, 100)}),
      );
      editor.graph.select(GraphSelection(nodes: {'output'}));
      editor.graph.setCamera(const GraphCamera(zoom: 2));
      expect(editor.compile(), same(first));
      expect(editor.compilationCount, 1);
      final field = shaderFields(
        shaderNodeDefinitionById['fragment_output']!,
      ).singleWhere((field) => field.id == 'alpha');
      editor.updateField('output', field, '0.5');
      expect(editor.compile().glsl, isNot(first.glsl));
      expect(editor.compilationCount, 2);
      editor.graph.undo();
      expect(editor.compile().glsl, first.glsl);
      expect(editor.compilationCount, 3);
    },
  );
  test(
    'deleting the selected output reconciles settings within the same undo step',
    () {
      final editor = ShaderEditorController(createDefaultShaderDocument());
      addTearDown(editor.dispose);
      final before = editor.document.graph;
      editor.graph.select(GraphSelection(nodes: {'output'}));
      editor.graph.deleteSelection();
      expect(editor.document.outputNodeId, isNull);
      expect(editor.compile().isValid, false);
      expect(editor.graph.undoCount, 1);
      editor.graph.undo();
      expect(editor.document.graph, before);
      expect(editor.document.outputNodeId, 'output');
      expect(editor.compile().isValid, true);
    },
  );
  test(
    'strict decoding retains unknown nodes and dangling connections for repair',
    () {
      final document = createShaderDocument(
        nodes: [
          createShaderNode(
            'unknown',
            'future',
            values: {
              'custom': [1, 2],
            },
          ),
        ],
        connections: [
          createShaderConnection(
            'broken',
            'missing',
            'value',
            'unknown',
            'input',
          ),
        ],
        outputNodeId: 'missing',
      );
      final restored = ShaderDocument.fromJson(document.toJson());
      final editor = ShaderEditorController(restored);
      addTearDown(editor.dispose);
      expect(editor.document.graph, document.graph);
      expect(editor.graph.resolution.diagnostics, isNotEmpty);
      expect(editor.document.connections.single.id, 'broken');
      expect(editor.document.nodes.single.shaderValues['custom'], [1, 2]);
      expect(editor.compile().isValid, false);
      expect(
        () => ShaderDocument.fromJson({'nodes': [], 'wires': []}),
        throwsFormatException,
      );
      expect(
        () =>
            ShaderDocument.fromJson({...document.toJson(), 'schemaVersion': 2}),
        throwsFormatException,
      );
    },
  );
  test('node preview is derived and cannot modify the authoring document', () {
    final document = createDefaultShaderDocument();
    final encoded = document.toJson();
    final preview = createShaderNodePreviewGraph(document, 'split_uv')!;
    expect(compileShaderGraph(preview).isValid, true);
    expect(document.toJson(), encoded);
    expect(document.outputNodeId, 'output');
    expect(preview.space.nodes.containsKey('split_uv'), true);
    expect(preview.outputNodeId, isNot('output'));
  });
}
