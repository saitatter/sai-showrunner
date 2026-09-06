import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:showrunner_flutter/plugins/overlays/shader_graph/shader_graph_compiler.dart';
import 'package:showrunner_flutter/plugins/overlays/shader_graph/shader_graph_editor.dart';
import 'package:showrunner_flutter/plugins/overlays/shader_graph/shader_graph_model.dart';
import 'package:showrunner_flutter/plugins/overlays/shader_graph/shader_node_definitions.dart';

void main() {
  group('shader graph model', () {
    test('round-trips graph data without losing frames or defaults', () {
      final graph = ShaderGraph(
        nodes: const [
          ShaderNodeInstance(
            id: 'parameter',
            defId: 'uniform_float',
            x: 10,
            y: 20,
            inputDefaults: {'name': 'pulse', 'value': '0.75'},
          ),
          ShaderNodeInstance(
            id: 'output',
            defId: 'fragment_output',
            x: 300,
            y: 20,
          ),
        ],
        wires: const [
          ShaderWire(
            id: 'wire',
            fromNode: 'parameter',
            fromPort: 'value',
            toNode: 'output',
            toPort: 'alpha',
          ),
        ],
        frames: const [
          ShaderFrame(
            id: 'frame',
            title: 'Parameters',
            color: '#7c4dff',
            x: 0,
            y: 0,
            width: 400,
            height: 200,
            nodeIds: ['parameter'],
          ),
        ],
        outputNodeId: 'output',
      );

      final restored = ShaderGraph.fromJson(graph.toJson());
      expect(restored.toJson(), graph.toJson());
      expect(restored.frames.single.nodeIds, ['parameter']);
    });

    test('starter graphs are valid and compile', () {
      for (final starter in shaderGraphStarters) {
        final graph = createShaderGraphStarter(starter.id);
        final result = compileShaderGraph(graph);
        expect(result.errors, isEmpty, reason: starter.id);
        expect(result.glsl, contains('void main()'), reason: starter.id);
      }
    });
  });

  group('shader graph compiler', () {
    test('catalog matches the complete upstream shader node set', () {
      expect(shaderNodeDefinitions, hasLength(84));
      expect(shaderNodeDefinitionById.keys, hasLength(84));
      expect(
        shaderNodeCategories,
        containsAll([
          'Input',
          'Math',
          'Noise',
          'Terrain',
          'Color',
          'Lighting',
          'Camera',
          'Output',
        ]),
      );
    });

    test('reports missing output and type mismatches', () {
      final graph = ShaderGraph(
        nodes: const [
          ShaderNodeInstance(id: 'uv', defId: 'uv', x: 0, y: 0),
          ShaderNodeInstance(id: 'add', defId: 'add', x: 100, y: 0),
        ],
        wires: const [
          ShaderWire(
            id: 'bad',
            fromNode: 'uv',
            fromPort: 'uv',
            toNode: 'add',
            toPort: 'a',
          ),
        ],
      );
      final errors = validateShaderGraph(graph);
      expect(
        errors,
        contains('Shader graph is missing a Fragment Output node.'),
      );
      expect(
        errors.any((error) => error.contains('incompatible types')),
        isTrue,
      );
    });

    test('reports cycles and duplicate uniform names', () {
      final graph = ShaderGraph(
        nodes: const [
          ShaderNodeInstance(
            id: 'a',
            defId: 'uniform_float',
            x: 0,
            y: 0,
            inputDefaults: {'name': 'pulse'},
          ),
          ShaderNodeInstance(
            id: 'b',
            defId: 'uniform_float',
            x: 0,
            y: 100,
            inputDefaults: {'name': 'pulse'},
          ),
          ShaderNodeInstance(id: 'one', defId: 'add', x: 100, y: 0),
        ],
        wires: const [
          ShaderWire(
            id: 'ab',
            fromNode: 'a',
            fromPort: 'value',
            toNode: 'one',
            toPort: 'a',
          ),
          ShaderWire(
            id: 'ba',
            fromNode: 'one',
            fromPort: 'result',
            toNode: 'a',
            toPort: 'value',
          ),
        ],
      );
      final errors = validateShaderGraph(graph);
      expect(
        errors,
        contains('Uniform name "u_pulse" is used by multiple parameter nodes.'),
      );
      expect(errors, contains('Shader graph contains a cycle.'));
      expect(wouldCreateShaderGraphCycle(graph, 'one', 'a'), isTrue);
    });

    test('collects uniform defaults, bindings and node previews', () {
      final graph = ShaderGraph(
        nodes: const [
          ShaderNodeInstance(
            id: 'value',
            defId: 'uniform_vec3',
            x: 0,
            y: 0,
            inputDefaults: {
              'name': 'accent',
              'value': 'vec3(0.2, 0.4, 0.8)',
              'bindingSource': 'config',
              'bindingPath': 'accentColor',
            },
          ),
          ShaderNodeInstance(
            id: 'output',
            defId: 'fragment_output',
            x: 300,
            y: 0,
          ),
        ],
        wires: const [
          ShaderWire(
            id: 'color',
            fromNode: 'value',
            fromPort: 'value',
            toNode: 'output',
            toPort: 'color',
          ),
        ],
        outputNodeId: 'output',
      );
      expect(collectShaderUniformDefaults(graph)['u_accent_custom'], [
        0.2,
        0.4,
        0.8,
      ]);
      expect(collectShaderUniformBindings(graph)['u_accent_custom'], {
        'source': 'config',
        'path': 'accentColor',
      });
      expect(
        createShaderNodePreviewGraph(graph, 'value')?.outputNodeId,
        '__preview_value_output',
      );
      expect(
        compileShaderGraph(graph).glsl,
        contains('uniform vec3 u_accent_custom;'),
      );
    });

    test('supports custom color ramp stops', () {
      final graph = ShaderGraph(
        nodes: const [
          ShaderNodeInstance(
            id: 'ramp',
            defId: 'color_ramp',
            x: 0,
            y: 0,
            inputDefaults: {
              'rampStops':
                  '[{"offset":0,"color":"#000000"},{"offset":1,"color":"#ffffff"}]',
            },
          ),
          ShaderNodeInstance(
            id: 'output',
            defId: 'fragment_output',
            x: 300,
            y: 0,
          ),
        ],
        wires: const [
          ShaderWire(
            id: 'color',
            fromNode: 'ramp',
            fromPort: 'color',
            toNode: 'output',
            toPort: 'color',
          ),
        ],
        outputNodeId: 'output',
      );
      final result = compileShaderGraph(graph);
      expect(result.errors, isEmpty);
      expect(result.glsl, contains('v0_ramp_color_ramp'));
      expect(result.glsl, contains('vec3(0.0, 0.0, 0.0)'));
      expect(result.glsl, contains('vec3(1.0, 1.0, 1.0)'));
    });

    test('compiles the standard three-stop color ramp path', () {
      final graph = createShaderGraphStarter('nebula');
      final result = compileShaderGraph(graph);
      expect(result.errors, isEmpty);
      expect(result.glsl, contains('smoothstep(0.0, max('));
      expect(result.glsl, isNot(contains('Unsupported node body: color_ramp')));
    });
  });

  testWidgets('renders the Shader Graph editor in Flutter', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(body: ShaderGraphEditorDialog(config: const {})),
      ),
    );
    await tester.pump();
    expect(find.text('Shader Graph'), findsOneWidget);
    expect(find.text('Input'), findsOneWidget);
    expect(find.text('Output'), findsOneWidget);
  });
}
