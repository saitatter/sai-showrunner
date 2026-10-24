import 'dart:convert';
import 'dart:io';
import 'package:sai_nodes_core/sai_nodes_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:showrunner_flutter/plugins/overlays/shader_graph/shader_graph_compiler.dart';
import 'package:showrunner_flutter/plugins/overlays/shader_graph/shader_graph_editor.dart';
import 'package:showrunner_flutter/plugins/overlays/shader_graph/shader_graph_model.dart';
import 'package:showrunner_flutter/plugins/overlays/shader_graph/shader_node_definitions.dart';
import 'package:showrunner_flutter/plugins/overlays/overlay_protocol.generated.dart';

void main() {
  test(
    'shader graph resource limits reject oversized work before compilation',
    () {
      final nodes = createShaderDocument(
        nodes: [
          for (
            var index = 0;
            index <= overlayRenderLimits['maxShaderNodes']!;
            index++
          )
            createShaderNode('node$index', 'float'),
        ],
        connections: [],
      );
      expect(compileShaderGraph(nodes).glsl, isEmpty);
      expect(
        validateShaderGraph(nodes),
        contains('Shader graph resource limits exceeded.'),
      );
      final uniforms = createShaderDocument(
        nodes: [
          createShaderNode('output', 'fragment_output'),
          for (
            var index = 0;
            index <= overlayRenderLimits['maxShaderUniforms']!;
            index++
          )
            createShaderNode('param$index', 'uniform_float'),
        ],
        connections: [],
      );
      expect(compileShaderGraph(uniforms).glsl, isEmpty);
      expect(
        validateShaderGraph(uniforms),
        contains('Shader uniform resource limit exceeded.'),
      );
    },
  );
  test(
    'every shader catalog node and starter generates a renderable fixture',
    () async {
      final fixtures = <Map<String, dynamic>>[];
      void add(String id, ShaderDocument graph) {
        final result = compileShaderGraph(graph);
        expect(result.errors, isEmpty, reason: id);
        expect(result.isValid, true, reason: id);
        fixtures.add({
          'id': id,
          'glsl': result.glsl,
          'graph': graph.toJson(),
          'uniforms': collectShaderUniformDefaults(graph),
          'bindings': collectShaderUniformBindings(graph),
        });
      }

      for (final definition in shaderNodeDefinitions) {
        final graph = createShaderDocument(
          nodes: [createShaderNode('probe', definition.id)],
          connections: [],
        );
        final preview = createShaderNodePreviewGraph(graph, 'probe');
        expect(preview, isNotNull, reason: definition.id);
        add(definition.id, preview!);
      }
      for (final starter in shaderGraphStarters) {
        add('starter-${starter.id}', createShaderGraphStarter(starter.id));
      }
      final unusual = createShaderDocument(
        nodes: [
          createShaderNode(
            '---',
            'uniform_float',
            values: {'name': '123', 'value': '0.5'},
          ),
        ],
        connections: [],
      );
      expect(
        getShaderUniformName(unusual.nodes.single),
        matches(RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$')),
      );
      add(
        'numeric-uniform-name',
        createShaderNodePreviewGraph(unusual, '---')!,
      );
      if (Platform.environment['SHOWRUNNER_EXPORT_SHADER_FIXTURES'] == '1') {
        final file = File('.tmp/shader-catalog.json');
        await file.parent.create(recursive: true);
        await file.writeAsString(jsonEncode(fixtures));
      }
    },
  );
  group('shader graph model', () {
    test('round-trips graph data without losing frames or defaults', () {
      final graph = createShaderDocument(
        nodes: [
          createShaderNode(
            'parameter',
            'uniform_float',
            values: {'name': 'pulse', 'value': '0.75'},
          ),
          createShaderNode('output', 'fragment_output'),
        ],
        connections: [
          createShaderConnection(
            'wire',
            'parameter',
            'value',
            'output',
            'alpha',
          ),
        ],
        presentations: {
          'parameter': NodePresentation(
            nodeId: 'parameter',
            position: const GraphPoint(10, 20),
          ),
          'output': NodePresentation(
            nodeId: 'output',
            position: const GraphPoint(300, 20),
          ),
        },
        frames: {
          'frame': GraphFrame(
            id: 'frame',
            title: 'Parameters',
            bounds: const GraphRect(0, 0, 400, 200),
            memberNodeIds: {'parameter'},
            metadata: {'color': '#7c4dff'},
          ),
        },
        outputNodeId: 'output',
      );

      final restored = ShaderDocument.fromJson(graph.toJson());
      expect(restored.toJson(), graph.toJson());
      expect(restored.space.frames.values.single.memberNodeIds, {'parameter'});
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
      final graph = createShaderDocument(
        nodes: [createShaderNode('uv', 'uv'), createShaderNode('add', 'add')],
        connections: [createShaderConnection('bad', 'uv', 'uv', 'add', 'a')],
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
      final graph = createShaderDocument(
        nodes: [
          createShaderNode('a', 'uniform_float', values: {'name': 'pulse'}),
          createShaderNode('b', 'uniform_float', values: {'name': 'pulse'}),
          createShaderNode('one', 'add'),
        ],
        connections: [
          createShaderConnection('ab', 'a', 'value', 'one', 'a'),
          createShaderConnection('ba', 'one', 'result', 'a', 'value'),
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
      final graph = createShaderDocument(
        nodes: [
          createShaderNode(
            'value',
            'uniform_vec3',
            values: {
              'name': 'accent',
              'value': 'vec3(0.2, 0.4, 0.8)',
              'bindingSource': 'config',
              'bindingPath': 'accentColor',
            },
          ),
          createShaderNode('output', 'fragment_output'),
        ],
        connections: [
          createShaderConnection('color', 'value', 'value', 'output', 'color'),
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
        createShaderNodePreviewGraph(graph, 'value')?.nodes
            .where((node) => node.shaderDefinitionId == 'fragment_output')
            .length,
        1,
      );
      expect(
        compileShaderGraph(graph).glsl,
        contains('uniform vec3 u_accent_custom;'),
      );
    });

    test('supports custom color ramp stops', () {
      final graph = createShaderDocument(
        nodes: [
          createShaderNode(
            'ramp',
            'color_ramp',
            values: {
              'rampStops':
                  '[{"offset":0,"color":"#000000"},{"offset":1,"color":"#ffffff"}]',
            },
          ),
          createShaderNode('output', 'fragment_output'),
        ],
        connections: [
          createShaderConnection('color', 'ramp', 'color', 'output', 'color'),
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
    await tester.binding.setSurfaceSize(const Size(1400, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(body: ShaderGraphEditorDialog(config: const {})),
      ),
    );
    await tester.pump();
    expect(find.text('Shader Graph'), findsOneWidget);
    expect(find.text('Input'), findsOneWidget);
    expect(find.text('Output'), findsAtLeastNWidgets(1));
  });
}
