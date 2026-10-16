import 'package:sai_nodes_core/sai_nodes_core.dart';

import 'shader_graph_compiler.dart';
import 'shader_graph_model.dart';
import 'shader_node_definitions.dart';

int shaderCategoryColor(String category) => switch (category) {
  'Input' || 'Inputs' => 0xff60a5fa,
  'Output' || 'Outputs' => 0xfff472b6,
  'Color' => 0xffc084fc,
  'Math' => 0xfffbbf24,
  _ => 0xff34d399,
};

List<ResolvedField> shaderFields(ShaderNodeDefinition definition) {
  ResolvedField text(String id, String label, [Object? fallback]) =>
      ResolvedField(
        id: id,
        label: label,
        kind: GraphFieldKind.string,
        dataPath: ['values', id],
        metadata: {'placement': 'inspector', 'defaultValue': fallback},
      );
  return [
    for (final port in definition.inputs)
      if (port.defaultValue != null)
        text(port.key, port.label, port.defaultValue),
    if ({
      'float_const',
      'vec3_const',
      'uniform_float',
      'uniform_vec2',
      'uniform_vec3',
    }.contains(definition.id))
      text('value', 'Value', definition.outputs.first.defaultValue ?? ''),
    if ({
      'uniform_float',
      'uniform_vec2',
      'uniform_vec3',
    }.contains(definition.id)) ...[
      text('name', 'Uniform name', ''),
      text('bindingSource', 'Binding source (config/state)', ''),
      text('bindingPath', 'Binding path', ''),
      text('bindingPlugin', 'Binding plugin', ''),
      text('bindingState', 'Binding state', ''),
    ],
    if (definition.id == 'color_ramp')
      ResolvedField(
        id: 'rampStops',
        label: 'Ramp stops JSON',
        kind: GraphFieldKind.json,
        dataPath: ['values', 'rampStops'],
        metadata: {
          'placement': 'inspector',
          'defaultValue': defaultShaderColorRampStops,
        },
      ),
  ];
}

NodeDefinitionRegistry createShaderDefinitions() => NodeDefinitionRegistry()
  ..replaceAll([
    for (final definition in shaderNodeDefinitions)
      DeclarativeNodeDefinition(
        type: 'shader.${definition.id}',
        displayName: definition.name,
        visualStyle: NodeVisualStyle(
          color: shaderCategoryColor(definition.category),
          category: definition.category,
          icon: 'shader',
        ),
        ports: [
          StaticPortFamily([
            for (final (direction, ports) in [
              (GraphPortDirection.input, definition.inputs),
              (GraphPortDirection.output, definition.outputs),
            ])
              for (final port in ports)
                ResolvedPort(
                  id: '${direction == GraphPortDirection.input ? 'in' : 'out'}:${port.key}',
                  direction: direction,
                  kind: GraphPortKind.data,
                  dataType: 'shader.${port.type.glsl}',
                  label: port.label,
                  maxConnections: direction == GraphPortDirection.input
                      ? 1
                      : null,
                ),
          ]),
        ],
        fields: [StaticFieldFamily(shaderFields(definition))],
      ),
  ]);

GraphTypeSystem createShaderTypes() => GraphTypeSystem(
  types: [
    for (final type in ShaderGlslType.values)
      GraphDataType(id: 'shader.${type.glsl}', label: type.glsl),
  ],
);

/// Owns only the canvas controller and a disposable compiler cache.
final class ShaderEditorController {
  ShaderEditorController(ShaderDocument document) {
    graph = GraphController(
      document: document.graph,
      activeSpaceId: shaderSpaceId,
      resolver: GraphResolver(
        definitions: createShaderDefinitions(),
        types: createShaderTypes(),
      ),
      documentPolicy: _reconcileOutput,
    );
  }
  late final GraphController graph;
  ShaderDocument get document => ShaderDocument(graph.document);
  int compilationCount = 0;
  int _compiledRevision = -1;
  ShaderGraphCompileResult? _compiled;
  ShaderGraphCompileResult compile() {
    if (_compiled == null || _compiledRevision != graph.semanticRevision) {
      _compiled = compileShaderGraph(document);
      _compiledRevision = graph.semanticRevision;
      compilationCount++;
    }
    return _compiled!;
  }

  void load(ShaderDocument document) {
    graph.replaceDocument(document.graph);
    _compiled = null;
  }

  void setOutput(String? id) => graph.execute(
    UpdateDocumentMetadataCommand(document.withOutput(id).graph.metadata),
    label: 'Select shader output',
  );
  void updateField(String nodeId, ResolvedField field, Object? value) {
    final node = document.space.nodes[nodeId]!;
    graph.execute(
      UpdateNodeDataCommand(shaderSpaceId, nodeId, {
        ...node.data,
        'values': {...node.shaderValues, field.id: value},
      }),
      label: 'Edit ${field.label}',
      coalesceKey: (nodeId, field.id),
    );
  }

  void dispose() => graph.dispose();
}

GraphDocument _reconcileOutput(GraphDocument before, GraphDocument candidate) {
  final previous = ShaderDocument(before);
  final next = ShaderDocument(candidate);
  final output = next.outputNodeId;
  if (output != null &&
      previous.space.nodes.containsKey(output) &&
      !next.space.nodes.containsKey(output)) {
    return next.withOutput(null).graph;
  }
  return candidate;
}
