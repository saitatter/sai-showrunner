// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:math' as math;

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

final class ShaderNodeInstance {
  const ShaderNodeInstance({
    required this.id,
    required this.defId,
    required this.x,
    required this.y,
    this.inputDefaults = const <String, dynamic>{},
  });

  final String id;
  final String defId;
  final double x;
  final double y;
  final Map<String, dynamic> inputDefaults;

  ShaderNodeInstance copyWith({
    String? id,
    String? defId,
    double? x,
    double? y,
    Map<String, dynamic>? inputDefaults,
  }) => ShaderNodeInstance(
    id: id ?? this.id,
    defId: defId ?? this.defId,
    x: x ?? this.x,
    y: y ?? this.y,
    inputDefaults:
        inputDefaults ?? Map<String, dynamic>.from(this.inputDefaults),
  );

  ShaderJsonMap toJson() => {
    'id': id,
    'defId': defId,
    'x': x,
    'y': y,
    if (inputDefaults.isNotEmpty) 'inputDefaults': _cloneValue(inputDefaults),
  };

  factory ShaderNodeInstance.fromJson(Map value) => ShaderNodeInstance(
    id: value['id'].toString(),
    defId: value['defId'].toString(),
    x: _finite(value['x'], 0),
    y: _finite(value['y'], 0),
    inputDefaults: value['inputDefaults'] is Map
        ? Map<String, dynamic>.from(value['inputDefaults'] as Map)
        : const <String, dynamic>{},
  );
}

final class ShaderWire {
  const ShaderWire({
    required this.id,
    required this.fromNode,
    required this.fromPort,
    required this.toNode,
    required this.toPort,
  });

  final String id;
  final String fromNode;
  final String fromPort;
  final String toNode;
  final String toPort;

  ShaderJsonMap toJson() => {
    'id': id,
    'fromNode': fromNode,
    'fromPort': fromPort,
    'toNode': toNode,
    'toPort': toPort,
  };

  factory ShaderWire.fromJson(Map value) => ShaderWire(
    id: value['id'].toString(),
    fromNode: value['fromNode'].toString(),
    fromPort: value['fromPort'].toString(),
    toNode: value['toNode'].toString(),
    toPort: value['toPort'].toString(),
  );
}

final class ShaderFrame {
  const ShaderFrame({
    required this.id,
    required this.title,
    required this.color,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.nodeIds = const <String>[],
  });

  final String id;
  final String title;
  final String color;
  final double x;
  final double y;
  final double width;
  final double height;
  final List<String> nodeIds;

  ShaderFrame copyWith({
    String? id,
    String? title,
    String? color,
    double? x,
    double? y,
    double? width,
    double? height,
    List<String>? nodeIds,
  }) => ShaderFrame(
    id: id ?? this.id,
    title: title ?? this.title,
    color: color ?? this.color,
    x: x ?? this.x,
    y: y ?? this.y,
    width: width ?? this.width,
    height: height ?? this.height,
    nodeIds: nodeIds ?? List<String>.from(this.nodeIds),
  );

  ShaderJsonMap toJson() => {
    'id': id,
    'title': title,
    'color': color,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    if (nodeIds.isNotEmpty) 'nodeIds': nodeIds,
  };

  factory ShaderFrame.fromJson(Map value) => ShaderFrame(
    id: value['id'].toString(),
    title: _text(value['title'], 'Frame'),
    color: _text(value['color'], '#7c4dff'),
    x: _finite(value['x'], 0),
    y: _finite(value['y'], 0),
    width: math.max(160, _finite(value['width'], 360)),
    height: math.max(96, _finite(value['height'], 220)),
    nodeIds: value['nodeIds'] is List
        ? (value['nodeIds'] as List).whereType<String>().toList()
        : const <String>[],
  );
}

final class ShaderGraph {
  const ShaderGraph({
    required this.nodes,
    required this.wires,
    this.frames = const <ShaderFrame>[],
    this.outputNodeId,
  });

  final List<ShaderNodeInstance> nodes;
  final List<ShaderWire> wires;
  final List<ShaderFrame> frames;
  final String? outputNodeId;

  ShaderGraph copyWith({
    List<ShaderNodeInstance>? nodes,
    List<ShaderWire>? wires,
    List<ShaderFrame>? frames,
    String? outputNodeId,
  }) => ShaderGraph(
    nodes: nodes ?? List<ShaderNodeInstance>.from(this.nodes),
    wires: wires ?? List<ShaderWire>.from(this.wires),
    frames: frames ?? List<ShaderFrame>.from(this.frames),
    outputNodeId: outputNodeId ?? this.outputNodeId,
  );

  ShaderJsonMap toJson() => {
    'nodes': nodes.map((node) => node.toJson()).toList(),
    'wires': wires.map((wire) => wire.toJson()).toList(),
    if (frames.isNotEmpty)
      'frames': frames.map((frame) => frame.toJson()).toList(),
    if (outputNodeId != null) 'outputNodeId': outputNodeId,
  };

  factory ShaderGraph.fromJson(Map value) {
    final rawNodes = value['nodes'];
    final rawWires = value['wires'];
    if (rawNodes is! List || rawWires is! List) {
      return createDefaultShaderGraph();
    }
    final nodes = rawNodes
        .whereType<Map>()
        .where((node) => node['id'] is String && node['defId'] is String)
        .map(ShaderNodeInstance.fromJson)
        .toList();
    final ids = nodes.map((node) => node.id).toSet();
    final wires = rawWires
        .whereType<Map>()
        .where(
          (wire) =>
              wire['id'] is String &&
              wire['fromNode'] is String &&
              wire['fromPort'] is String &&
              wire['toNode'] is String &&
              wire['toPort'] is String &&
              ids.contains(wire['fromNode']) &&
              ids.contains(wire['toNode']),
        )
        .map(ShaderWire.fromJson)
        .toList();
    if (nodes.isEmpty) return createDefaultShaderGraph();
    final frames = value['frames'] is List
        ? (value['frames'] as List)
              .whereType<Map>()
              .where((frame) => frame['id'] is String)
              .map(ShaderFrame.fromJson)
              .map(
                (frame) => frame.copyWith(
                  nodeIds: frame.nodeIds.where(ids.contains).toList(),
                ),
              )
              .toList()
        : const <ShaderFrame>[];
    final requestedOutput = value['outputNodeId'];
    final output = requestedOutput is String && ids.contains(requestedOutput)
        ? requestedOutput
        : nodes
              .where((node) => node.defId == 'fragment_output')
              .map((node) => node.id)
              .firstOrNull;
    return ShaderGraph(
      nodes: nodes,
      wires: wires,
      frames: frames,
      outputNodeId: output,
    );
  }
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

ShaderGraph createDefaultShaderGraph() => ShaderGraph(
  nodes: const [
    ShaderNodeInstance(id: 'uv', defId: 'uv', x: 40, y: 180),
    ShaderNodeInstance(id: 'split_uv', defId: 'vec2_split', x: 260, y: 180),
    ShaderNodeInstance(id: 'accent', defId: 'accent_color', x: 260, y: 20),
    ShaderNodeInstance(
      id: 'secondary',
      defId: 'secondary_color',
      x: 260,
      y: 340,
    ),
    ShaderNodeInstance(id: 'gradient', defId: 'mix_color', x: 520, y: 180),
    ShaderNodeInstance(id: 'output', defId: 'fragment_output', x: 780, y: 190),
  ],
  wires: const [
    ShaderWire(
      id: 'uv:uv->split_uv:v',
      fromNode: 'uv',
      fromPort: 'uv',
      toNode: 'split_uv',
      toPort: 'v',
    ),
    ShaderWire(
      id: 'accent:color->gradient:a',
      fromNode: 'accent',
      fromPort: 'color',
      toNode: 'gradient',
      toPort: 'a',
    ),
    ShaderWire(
      id: 'secondary:color->gradient:b',
      fromNode: 'secondary',
      fromPort: 'color',
      toNode: 'gradient',
      toPort: 'b',
    ),
    ShaderWire(
      id: 'split_uv:x->gradient:t',
      fromNode: 'split_uv',
      fromPort: 'x',
      toNode: 'gradient',
      toPort: 't',
    ),
    ShaderWire(
      id: 'gradient:result->output:color',
      fromNode: 'gradient',
      fromPort: 'result',
      toNode: 'output',
      toPort: 'color',
    ),
  ],
  outputNodeId: 'output',
);

ShaderGraph createShaderGraphStarter(String id) {
  final nodes = <ShaderNodeInstance>[];
  final wires = <ShaderWire>[];
  void node(
    String nodeId,
    String defId,
    double x,
    double y, [
    Map<String, dynamic> defaults = const {},
  ]) => nodes.add(
    ShaderNodeInstance(
      id: nodeId,
      defId: defId,
      x: x,
      y: y,
      inputDefaults: defaults,
    ),
  );
  void wire(
    String id,
    String from,
    String fromPort,
    String to,
    String toPort,
  ) => wires.add(
    ShaderWire(
      id: id,
      fromNode: from,
      fromPort: fromPort,
      toNode: to,
      toPort: toPort,
    ),
  );

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
      return createDefaultShaderGraph();
  }
  return ShaderGraph(nodes: nodes, wires: wires, outputNodeId: 'output');
}

ShaderGraph cloneShaderGraph(ShaderGraph graph) =>
    ShaderGraph.fromJson(graph.toJson());

ShaderJsonMap applyCompiledShaderGraph({
  required ShaderJsonMap config,
  required ShaderGraph graph,
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
  if (value is Map)
    return {
      for (final entry in value.entries)
        '${entry.key}': _cloneValue(entry.value),
    };
  if (value is List) return value.map(_cloneValue).toList();
  return value;
}

double _finite(dynamic value, double fallback) =>
    value is num && value.isFinite ? value.toDouble() : fallback;

String _text(dynamic value, String fallback) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? fallback : text;
}
