import 'package:sai_nodes_core/sai_nodes_core.dart';

typedef ShaderJsonMap = Map<String, dynamic>;

enum ShaderGlslType { float, vec2, vec3, vec4 }

extension ShaderGlslTypeName on ShaderGlslType {
  String get glsl => switch (this) {
    ShaderGlslType.float => 'float',
    ShaderGlslType.vec2 => 'vec2',
    ShaderGlslType.vec3 => 'vec3',
    ShaderGlslType.vec4 => 'vec4',
  };
}

final class ShaderPortDefinition {
  const ShaderPortDefinition({
    required this.key,
    required this.label,
    required this.type,
    this.defaultValue,
  });

  final String key;
  final String label;
  final ShaderGlslType type;
  final String? defaultValue;
}

const shaderSpaceId = 'space:shader';

/// Shader authoring has one immutable document. GLSL and uniforms are derived.
final class ShaderDocument {
  ShaderDocument(this.graph) {
    if (!graph.spaces.containsKey(shaderSpaceId)) {
      throw const FormatException('Shader document requires space:shader.');
    }
    final settings = graph.metadata['shader'];
    if (settings is! Map ||
        settings.keys.any((key) => key != 'outputNodeId') ||
        (settings['outputNodeId'] != null &&
            settings['outputNodeId'] is! String)) {
      throw const FormatException('Invalid shader document settings.');
    }
  }
  factory ShaderDocument.fromJson(Map value) =>
      ShaderDocument(GraphDocument.fromJson(Map<String, Object?>.from(value)));
  final GraphDocument graph;
  GraphSpace get space => graph.spaces[shaderSpaceId]!;
  List<GraphNode> get nodes => List.unmodifiable(space.nodes.values);
  List<GraphConnection> get connections =>
      List.unmodifiable(space.connections.values);
  String? get outputNodeId =>
      (graph.metadata['shader'] as Map)['outputNodeId'] as String?;
  GraphJson toJson() => graph.toJson();
  ShaderDocument withOutput(String? id) => ShaderDocument(
    graph.copyWith(
      metadata: {
        ...graph.metadata,
        'shader': {'outputNodeId': id},
      },
    ),
  );
}

extension ShaderNodeSemantics on GraphNode {
  String get shaderDefinitionId =>
      type.startsWith('shader.') ? type.substring(7) : type;
  GraphJson get shaderValues => data['values'] is Map
      ? Map<String, Object?>.from(data['values'] as Map)
      : const {};
}

GraphNode createShaderNode(
  String id,
  String definition, {
  GraphJson values = const {},
}) => GraphNode(id: id, type: 'shader.$definition', data: {'values': values});

GraphConnection createShaderConnection(
  String id,
  String from,
  String output,
  String to,
  String input,
) => GraphConnection(
  id: id,
  kind: GraphConnectionKind.data,
  from: PortRef(nodeId: from, portId: 'out:$output'),
  to: PortRef(nodeId: to, portId: 'in:$input'),
);

ShaderDocument createShaderDocument({
  String? id,
  Iterable<GraphNode> nodes = const [],
  Iterable<GraphConnection> connections = const [],
  Map<String, NodePresentation> presentations = const {},
  Map<String, GraphFrame> frames = const {},
  String? outputNodeId,
}) => ShaderDocument(
  GraphDocument(
    id: id ?? newGraphId(),
    spaces: {
      shaderSpaceId: GraphSpace(
        id: shaderSpaceId,
        nodes: {for (final node in nodes) node.id: node},
        connections: {for (final edge in connections) edge.id: edge},
        nodePresentations: presentations,
        frames: frames,
      ),
    },
    metadata: {
      'shader': {'outputNodeId': outputNodeId},
    },
  ),
);

final class _ShaderDocumentBuilder {
  final nodes = <String, GraphNode>{};
  final connections = <String, GraphConnection>{};
  final presentations = <String, NodePresentation>{};
  void node(
    String id,
    String definition,
    double x,
    double y, [
    GraphJson values = const {},
  ]) {
    nodes[id] = createShaderNode(id, definition, values: values);
    presentations[id] = NodePresentation(
      nodeId: id,
      position: GraphPoint(x, y),
    );
  }

  void wire(String id, String from, String output, String to, String input) {
    connections[id] = createShaderConnection(id, from, output, to, input);
  }

  ShaderDocument build({String? outputNodeId}) => createShaderDocument(
    nodes: nodes.values,
    connections: connections.values,
    presentations: presentations,
    outputNodeId: outputNodeId,
  );
}

const defaultShaderColorRampStops = <ShaderJsonMap>[
  {'offset': 0.0, 'color': 'vec3(0.08, 0.20, 0.08)'},
  {'offset': 0.55, 'color': 'vec3(0.42, 0.34, 0.22)'},
  {'offset': 1.0, 'color': 'vec3(0.92, 0.92, 0.86)'},
];

final class ShaderGraphStarter {
  const ShaderGraphStarter({
    required this.id,
    required this.name,
    required this.description,
  });

  final String id;
  final String name;
  final String description;
}

const shaderGraphStarters = <ShaderGraphStarter>[
  ShaderGraphStarter(
    id: 'procedural-terrain',
    name: 'Procedural Terrain',
    description: 'FBM terrain with altitude bands and simple sunlight.',
  ),
  ShaderGraphStarter(
    id: 'nebula',
    name: 'Nebula',
    description: 'Warped cloud colors for atmospheric overlays.',
  ),
  ShaderGraphStarter(
    id: 'audio-reactive',
    name: 'Audio Reactive',
    description: 'Intensity-driven bands for music or alerts.',
  ),
  ShaderGraphStarter(
    id: 'energy-field',
    name: 'Energy Field',
    description: 'Voronoi and wave-driven animated energy.',
  ),
];

ShaderDocument createDefaultShaderDocument() {
  final builder = _ShaderDocumentBuilder();
  builder.node('uv', 'uv', 40, 180);
  builder.node('split_uv', 'vec2_split', 360, 180);
  builder.node('accent', 'accent_color', 360, 20);
  builder.node('secondary', 'secondary_color', 360, 420);
  builder.node('gradient', 'mix_color', 680, 180);
  builder.node('output', 'fragment_output', 1000, 190);
  builder.wire('uv:uv->split_uv:v', 'uv', 'uv', 'split_uv', 'v');
  builder.wire('accent:color->gradient:a', 'accent', 'color', 'gradient', 'a');
  builder.wire(
    'secondary:color->gradient:b',
    'secondary',
    'color',
    'gradient',
    'b',
  );
  builder.wire('split_uv:x->gradient:t', 'split_uv', 'x', 'gradient', 't');
  builder.wire(
    'gradient:result->output:color',
    'gradient',
    'result',
    'output',
    'color',
  );
  return builder.build(outputNodeId: 'output');
}

ShaderDocument createShaderGraphStarter(String id) {
  final builder = _ShaderDocumentBuilder();
  void node(
    String id,
    String definition,
    double x,
    double y, [
    GraphJson values = const {},
  ]) => builder.node(id, definition, x * 1.4, y * 1.5, values);
  final wire = builder.wire;
  switch (id) {
    case 'procedural-terrain':
      node('uv', 'uv', 40, 220);
      node('warp', 'domain_warp', 260, 180, {
        'scale': '2.2',
        'strength': '0.22',
      });
      node('base', 'fbm_noise', 500, 160, {'scale': '3.5', 'octaves': '6.0'});
      node('detail', 'value_noise', 500, 340, {'scale': '18.0'});
      node('height', 'terrain_height', 760, 200, {'detailStrength': '0.18'});
      node('bands', 'altitude_bands', 1020, 180);
      node('normal', 'normal_from_height', 1020, 420, {'strength': '1.6'});
      node('sun', 'sun_direction', 1260, 420);
      node('light', 'diffuse_lighting', 1500, 220, {'ambient': '0.28'});
      node('output', 'fragment_output', 1740, 240);
      wire('uv:uv->warp:uv', 'uv', 'uv', 'warp', 'uv');
      wire('warp:uv->base:uv', 'warp', 'uv', 'base', 'uv');
      wire('warp:uv->detail:uv', 'warp', 'uv', 'detail', 'uv');
      wire('base:value->height:base', 'base', 'value', 'height', 'base');
      wire(
        'detail:value->height:detail',
        'detail',
        'value',
        'height',
        'detail',
      );
      wire(
        'height:height->bands:height',
        'height',
        'height',
        'bands',
        'height',
      );
      wire(
        'height:height->normal:center',
        'height',
        'height',
        'normal',
        'center',
      );
      wire(
        'height:height->normal:right',
        'height',
        'height',
        'normal',
        'right',
      );
      wire('height:height->normal:up', 'height', 'height', 'normal', 'up');
      wire('bands:color->light:color', 'bands', 'color', 'light', 'color');
      wire(
        'normal:normal->light:normal',
        'normal',
        'normal',
        'light',
        'normal',
      );
      wire(
        'sun:direction->light:lightDir',
        'sun',
        'direction',
        'light',
        'lightDir',
      );
      wire('light:color->output:color', 'light', 'color', 'output', 'color');
    case 'nebula':
      node('uv', 'uv', 40, 220);
      node('time', 'time', 40, 420);
      node('warp', 'domain_warp', 300, 220, {
        'scale': '2.8',
        'strength': '0.35',
      });
      node('noise', 'fbm_noise', 560, 220, {'scale': '5.0', 'octaves': '6.0'});
      node('ramp', 'color_ramp', 820, 220, {
        'low': 'vec3(0.04, 0.03, 0.12)',
        'mid': 'vec3(0.42, 0.12, 0.70)',
        'high': 'vec3(0.05, 0.75, 1.0)',
      });
      node('output', 'fragment_output', 1080, 240);
      wire('uv:uv->warp:uv', 'uv', 'uv', 'warp', 'uv');
      wire('warp:uv->noise:uv', 'warp', 'uv', 'noise', 'uv');
      wire('noise:value->ramp:factor', 'noise', 'value', 'ramp', 'factor');
      wire('ramp:color->output:color', 'ramp', 'color', 'output', 'color');
    case 'audio-reactive':
      node('uv', 'uv', 40, 180);
      node('split', 'vec2_split', 260, 180);
      node('time', 'time', 260, 360);
      node('intensity', 'intensity', 260, 500);
      node('wave', 'wave', 520, 220, {'frequency': '24.0', 'speed': '3.0'});
      node('mix', 'multiply', 760, 260);
      node('gradient', 'gradient_color', 1000, 240);
      node('output', 'fragment_output', 1240, 260);
      wire('uv:uv->split:v', 'uv', 'uv', 'split', 'v');
      wire('split:y->wave:x', 'split', 'y', 'wave', 'x');
      wire('time:t->wave:time', 'time', 't', 'wave', 'time');
      wire('wave:result->mix:a', 'wave', 'result', 'mix', 'a');
      wire('intensity:value->mix:b', 'intensity', 'value', 'mix', 'b');
      wire(
        'mix:result->gradient:factor',
        'mix',
        'result',
        'gradient',
        'factor',
      );
      wire(
        'gradient:color->output:color',
        'gradient',
        'color',
        'output',
        'color',
      );
    case 'energy-field':
      node('uv', 'uv', 40, 200);
      node('time', 'time', 40, 420);
      node('voronoi', 'voronoi_noise', 300, 180, {
        'scale': '14.0',
        'jitter': '0.9',
      });
      node('split', 'vec2_split', 300, 380);
      node('wave', 'wave', 560, 360, {'frequency': '18.0', 'speed': '2.5'});
      node('mix', 'mix_float', 800, 240, {'t': '0.5'});
      node('ramp', 'color_ramp', 1040, 240, {
        'low': 'vec3(0.0, 0.05, 0.08)',
        'mid': 'vec3(0.0, 0.8, 1.0)',
        'high': 'vec3(1.0, 1.0, 1.0)',
      });
      node('output', 'fragment_output', 1280, 260);
      wire('uv:uv->voronoi:uv', 'uv', 'uv', 'voronoi', 'uv');
      wire('uv:uv->split:v', 'uv', 'uv', 'split', 'v');
      wire('split:x->wave:x', 'split', 'x', 'wave', 'x');
      wire('time:t->wave:time', 'time', 't', 'wave', 'time');
      wire('voronoi:distance->mix:a', 'voronoi', 'distance', 'mix', 'a');
      wire('wave:result->mix:b', 'wave', 'result', 'mix', 'b');
      wire('mix:result->ramp:factor', 'mix', 'result', 'ramp', 'factor');
      wire('ramp:color->output:color', 'ramp', 'color', 'output', 'color');
    default:
      return createDefaultShaderDocument();
  }
  return builder.build(outputNodeId: 'output');
}

ShaderJsonMap applyCompiledShaderGraph({
  required ShaderJsonMap config,
  required ShaderDocument graph,
  required String glsl,
  Map<String, dynamic> uniforms = const {},
  Map<String, dynamic> bindings = const {},
}) => {
  ...config,
  'preset': 'custom',
  'shaderGraph': graph.toJson(),
  'customFragmentShader': glsl,
  'shaderUniforms': _cloneValue(uniforms),
  'shaderUniformBindings': _cloneValue(bindings),
};

dynamic _cloneValue(dynamic value) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        '${entry.key}': _cloneValue(entry.value),
    };
  }
  if (value is List) return value.map(_cloneValue).toList();
  return value;
}
