// ignore_for_file: curly_braces_in_flow_control_structures, unnecessary_brace_in_string_interps

import 'dart:convert';

import 'shader_graph_model.dart';
import 'shader_node_definitions.dart';

const _builtInUniforms = {
  'u_resolution',
  'u_time',
  'u_accent',
  'u_secondary',
  'u_intensity',
  'u_speed',
  'u_camera_position',
  'u_camera_target',
  'u_mouse',
};

final class ShaderGraphCompileResult {
  const ShaderGraphCompileResult({
    required this.glsl,
    required this.errors,
    required this.warnings,
  });

  final String glsl;
  final List<String> errors;
  final List<String> warnings;
  bool get isValid => errors.isEmpty && glsl.isNotEmpty;
}

ShaderPortDefinition? getShaderPortDefinition(
  ShaderGraph graph,
  String nodeId,
  String portKey, {
  required bool input,
}) {
  final node = graph.nodes.where((item) => item.id == nodeId).firstOrNull;
  final definition = node == null ? null : shaderNodeDefinitionById[node.defId];
  if (definition == null) return null;
  final ports = input ? definition.inputs : definition.outputs;
  return ports.where((port) => port.key == portKey).firstOrNull;
}

bool areShaderTypesCompatible(ShaderGlslType from, ShaderGlslType to) =>
    from == to;

List<String> _topologicalSort(ShaderGraph graph) {
  final ids = graph.nodes.map((node) => node.id).toSet();
  final degree = {for (final id in ids) id: 0};
  final adjacency = {for (final id in ids) id: <String>[]};
  for (final wire in graph.wires) {
    if (!ids.contains(wire.fromNode) || !ids.contains(wire.toNode)) continue;
    adjacency[wire.fromNode]!.add(wire.toNode);
    degree[wire.toNode] = degree[wire.toNode]! + 1;
  }
  final queue = <String>[
    for (final node in graph.nodes)
      if (degree[node.id] == 0) node.id,
  ];
  final sorted = <String>[];
  while (queue.isNotEmpty) {
    final id = queue.removeAt(0);
    sorted.add(id);
    for (final neighbor in adjacency[id]!) {
      degree[neighbor] = degree[neighbor]! - 1;
      if (degree[neighbor] == 0) queue.add(neighbor);
    }
  }
  return sorted;
}

bool shaderGraphHasCycle(ShaderGraph graph) =>
    _topologicalSort(graph).length != graph.nodes.length;

bool wouldCreateShaderGraphCycle(
  ShaderGraph graph,
  String fromNode,
  String toNode,
) {
  if (fromNode == toNode) return true;
  return shaderGraphHasCycle(
    graph.copyWith(
      wires: [
        ...graph.wires,
        ShaderWire(
          id: '__candidate',
          fromNode: fromNode,
          fromPort: '',
          toNode: toNode,
          toPort: '',
        ),
      ],
    ),
  );
}

List<String> validateShaderGraph(ShaderGraph graph) {
  final errors = <String>[];
  final nodeById = {for (final node in graph.nodes) node.id: node};
  final outputNodes = graph.nodes
      .where((node) => node.defId == 'fragment_output')
      .toList();

  for (final node in graph.nodes) {
    if (!shaderNodeDefinitionById.containsKey(node.defId)) {
      errors.add(
        'Node ${node.id} uses unknown shader node type "${node.defId}".',
      );
    }
  }

  final uniformNames = <String>{};
  for (final node in graph.nodes) {
    if (!{'uniform_float', 'uniform_vec2', 'uniform_vec3'}.contains(node.defId))
      continue;
    final name = getShaderUniformName(node);
    if (!uniformNames.add(name)) {
      errors.add('Uniform name "$name" is used by multiple parameter nodes.');
    }
  }

  if (graph.outputNodeId != null) {
    final output = nodeById[graph.outputNodeId];
    if (output == null) {
      errors.add(
        'Shader graph output node "${graph.outputNodeId}" is missing.',
      );
    } else if (output.defId != 'fragment_output') {
      errors.add(
        'Shader graph output node "${graph.outputNodeId}" is not a Fragment Output node.',
      );
    }
  } else if (outputNodes.isEmpty) {
    errors.add('Shader graph is missing a Fragment Output node.');
  } else if (outputNodes.length > 1) {
    errors.add(
      'Shader graph has multiple Fragment Output nodes. Pick one output node before compiling.',
    );
  }

  final inputTargets = <String>{};
  for (final wire in graph.wires) {
    final fromNode = nodeById[wire.fromNode];
    final toNode = nodeById[wire.toNode];
    if (fromNode == null) {
      errors.add('Wire ${wire.id} starts at missing node "${wire.fromNode}".');
      continue;
    }
    if (toNode == null) {
      errors.add('Wire ${wire.id} ends at missing node "${wire.toNode}".');
      continue;
    }
    final fromPort = getShaderPortDefinition(
      graph,
      wire.fromNode,
      wire.fromPort,
      input: false,
    );
    final toPort = getShaderPortDefinition(
      graph,
      wire.toNode,
      wire.toPort,
      input: true,
    );
    if (fromPort == null) {
      errors.add(
        'Wire ${wire.id} starts at missing output port "${wire.fromNode}:${wire.fromPort}".',
      );
    }
    if (toPort == null) {
      errors.add(
        'Wire ${wire.id} ends at missing input port "${wire.toNode}:${wire.toPort}".',
      );
    }
    if (fromPort != null &&
        toPort != null &&
        !areShaderTypesCompatible(fromPort.type, toPort.type)) {
      errors.add(
        'Wire ${wire.id} connects incompatible types: ${fromPort.type.glsl} -> ${toPort.type.glsl}.',
      );
    }
    final target = '${wire.toNode}:${wire.toPort}';
    if (!inputTargets.add(target))
      errors.add('Input port "$target" has multiple incoming wires.');
  }
  if (shaderGraphHasCycle(graph)) errors.add('Shader graph contains a cycle.');
  return errors;
}

List<String> collectShaderGraphWarnings(ShaderGraph graph) {
  final warnings = <String>[];
  final nodeById = {for (final node in graph.nodes) node.id: node};
  final output =
      (graph.outputNodeId == null ? null : nodeById[graph.outputNodeId]) ??
      graph.nodes.where((node) => node.defId == 'fragment_output').firstOrNull;
  if (output == null || output.defId != 'fragment_output') return warnings;
  if (!graph.wires.any(
    (wire) => wire.toNode == output.id && wire.toPort == 'color',
  )) {
    warnings.add(
      'Fragment Output "${_nodeLabel(output)}" has no color input connected; it will render black.',
    );
  }
  final dependencies = _dependencies(graph, output.id);
  for (final node in graph.nodes) {
    if (dependencies.contains(node.id) || node.defId == 'fragment_output')
      continue;
    warnings.add(
      'Node "${_nodeLabel(node)}" is not connected to the active Fragment Output.',
    );
  }
  return warnings;
}

Set<String> _dependencies(ShaderGraph graph, String outputId) {
  final reverse = <String, List<String>>{};
  for (final wire in graph.wires)
    reverse.putIfAbsent(wire.toNode, () => []).add(wire.fromNode);
  final visited = <String>{};
  final stack = [outputId];
  while (stack.isNotEmpty) {
    final id = stack.removeLast();
    if (!visited.add(id)) continue;
    stack.addAll(reverse[id] ?? const []);
  }
  return visited;
}

String _nodeLabel(ShaderNodeInstance node) =>
    shaderNodeDefinitionById[node.defId]?.name ?? node.defId;

String shaderGlslDefault(ShaderGlslType type) => switch (type) {
  ShaderGlslType.float => '0.0',
  ShaderGlslType.vec2 => 'vec2(0.0)',
  ShaderGlslType.vec3 => 'vec3(0.0)',
  ShaderGlslType.vec4 => 'vec4(0.0, 0.0, 0.0, 1.0)',
};

String getShaderUniformName(ShaderNodeInstance node) {
  final raw = node.inputDefaults['name']?.toString().trim() ?? '';
  final fallback = 'parameter_${node.id}';
  var safe = (raw.isEmpty ? fallback : raw).replaceAll(
    RegExp(r'[^a-zA-Z0-9_]'),
    '_',
  );
  safe = safe.replaceFirst(RegExp(r'^[^a-zA-Z_]+'), '');
  final base = safe.isEmpty ? fallback : safe;
  final name = base.startsWith('u_') ? base : 'u_$base';
  return _builtInUniforms.contains(name) ? '${name}_custom' : name;
}

Map<String, dynamic> collectShaderUniformDefaults(ShaderGraph graph) {
  final values = <String, dynamic>{};
  for (final node in graph.nodes) {
    final name = getShaderUniformName(node);
    final value = _nodeValue(
      node,
      node.defId == 'uniform_vec3'
          ? 'vec3(1.0, 1.0, 1.0)'
          : node.defId == 'uniform_vec2'
          ? 'vec2(0.0, 0.0)'
          : '1.0',
    );
    if (node.defId == 'uniform_float')
      values[name] = double.tryParse(value) ?? 1;
    if (node.defId == 'uniform_vec2')
      values[name] = _parseVector(value, 2, [0, 0]);
    if (node.defId == 'uniform_vec3')
      values[name] = _parseVector(value, 3, [1, 1, 1]);
  }
  return values;
}

Map<String, dynamic> collectShaderUniformBindings(ShaderGraph graph) {
  final bindings = <String, dynamic>{};
  for (final node in graph.nodes) {
    if (!{'uniform_float', 'uniform_vec2', 'uniform_vec3'}.contains(node.defId))
      continue;
    final source = node.inputDefaults['bindingSource']?.toString();
    final name = getShaderUniformName(node);
    if (source == 'config') {
      final path = node.inputDefaults['bindingPath']?.toString().trim() ?? '';
      if (path.isNotEmpty) bindings[name] = {'source': source, 'path': path};
    } else if (source == 'state') {
      final plugin =
          node.inputDefaults['bindingPlugin']?.toString().trim() ?? '';
      final state = node.inputDefaults['bindingState']?.toString().trim() ?? '';
      final path = node.inputDefaults['bindingPath']?.toString().trim() ?? '';
      if (plugin.isNotEmpty && state.isNotEmpty && path.isNotEmpty) {
        bindings[name] = {
          'source': source,
          'plugin': plugin,
          'state': state,
          'path': path,
        };
      }
    }
  }
  return bindings;
}

ShaderGraph? createShaderNodePreviewGraph(ShaderGraph graph, String nodeId) {
  final node = graph.nodes.where((item) => item.id == nodeId).firstOrNull;
  final definition = node == null ? null : shaderNodeDefinitionById[node.defId];
  if (node == null || definition == null) return null;
  if (node.defId == 'fragment_output')
    return graph.copyWith(outputNodeId: node.id);
  final port =
      definition.outputs
          .where((item) => item.type == ShaderGlslType.vec3)
          .firstOrNull ??
      definition.outputs
          .where((item) => item.type == ShaderGlslType.float)
          .firstOrNull ??
      definition.outputs
          .where((item) => item.type == ShaderGlslType.vec2)
          .firstOrNull;
  if (port == null) return null;
  final nodes = graph.nodes
      .where((item) => item.defId != 'fragment_output')
      .map((item) => item.copyWith())
      .toList();
  final ids = nodes.map((item) => item.id).toSet();
  final wires = graph.wires
      .where((wire) => ids.contains(wire.fromNode) && ids.contains(wire.toNode))
      .toList();
  final outputId = '__preview_${node.id}_output';
  if (port.type == ShaderGlslType.vec3) {
    return ShaderGraph(
      nodes: [
        ...nodes,
        ShaderNodeInstance(
          id: outputId,
          defId: 'fragment_output',
          x: node.x + 240,
          y: node.y,
        ),
      ],
      wires: [
        ...wires,
        ShaderWire(
          id: '${node.id}:${port.key}->${outputId}:color',
          fromNode: node.id,
          fromPort: port.key,
          toNode: outputId,
          toPort: 'color',
        ),
      ],
      outputNodeId: outputId,
    );
  }
  final composeId = '__preview_${node.id}_color';
  final previewNodes = [
    ...nodes,
    ShaderNodeInstance(
      id: composeId,
      defId: 'vec3_compose',
      x: node.x + 240,
      y: node.y,
    ),
    ShaderNodeInstance(
      id: outputId,
      defId: 'fragment_output',
      x: node.x + 480,
      y: node.y,
    ),
  ];
  final previewWires = [
    ...wires,
    ShaderWire(
      id: '$composeId:result->$outputId:color',
      fromNode: composeId,
      fromPort: 'result',
      toNode: outputId,
      toPort: 'color',
    ),
  ];
  if (port.type == ShaderGlslType.float) {
    for (final component in ['x', 'y', 'z']) {
      previewWires.add(
        ShaderWire(
          id: '${node.id}:${port.key}->${composeId}:$component',
          fromNode: node.id,
          fromPort: port.key,
          toNode: composeId,
          toPort: component,
        ),
      );
    }
  } else {
    final splitId = '__preview_${node.id}_split';
    previewNodes.insert(
      previewNodes.length - 2,
      ShaderNodeInstance(
        id: splitId,
        defId: 'vec2_split',
        x: node.x + 240,
        y: node.y,
      ),
    );
    previewWires.add(
      ShaderWire(
        id: '${node.id}:${port.key}->${splitId}:v',
        fromNode: node.id,
        fromPort: port.key,
        toNode: splitId,
        toPort: 'v',
      ),
    );
    previewWires.add(
      ShaderWire(
        id: '${splitId}:x->$composeId:x',
        fromNode: splitId,
        fromPort: 'x',
        toNode: composeId,
        toPort: 'x',
      ),
    );
    previewWires.add(
      ShaderWire(
        id: '${splitId}:y->$composeId:y',
        fromNode: splitId,
        fromPort: 'y',
        toNode: composeId,
        toPort: 'y',
      ),
    );
  }
  return ShaderGraph(
    nodes: previewNodes,
    wires: previewWires,
    outputNodeId: outputId,
  );
}

ShaderGraphCompileResult compileShaderGraph(ShaderGraph graph) {
  final errors = validateShaderGraph(graph);
  if (errors.isNotEmpty)
    return ShaderGraphCompileResult(
      glsl: '',
      errors: errors,
      warnings: const [],
    );
  final warnings = collectShaderGraphWarnings(graph);
  final sorted = _topologicalSort(graph);
  final byId = {for (final node in graph.nodes) node.id: node};
  final variables = <String, Map<String, String>>{};
  final body = <String>[];
  final uniforms = <String>{};
  var counter = 0;
  for (final id in sorted) {
    final node = byId[id]!;
    final definition = shaderNodeDefinitionById[node.defId]!;
    variables[id] = {
      for (final port in definition.outputs)
        port.key:
            'v${counter++}_${id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}_${port.key}',
    };
  }
  final wireMap = <String, ShaderWire>{
    for (final wire in graph.wires) '${wire.toNode}:${wire.toPort}': wire,
  };
  for (final id in sorted) {
    final node = byId[id]!;
    final definition = shaderNodeDefinitionById[node.defId]!;
    final input = <String, String>{};
    for (final port in definition.inputs) {
      final wire = wireMap['$id:${port.key}'];
      if (wire != null) {
        input[port.key] =
            variables[wire.fromNode]?[wire.fromPort] ??
            port.defaultValue ??
            shaderGlslDefault(port.type);
      } else {
        input[port.key] =
            node.inputDefaults[port.key]?.toString() ??
            port.defaultValue ??
            shaderGlslDefault(port.type);
      }
    }
    final output = variables[id]!;
    for (final port in definition.outputs)
      body.add('\t${port.type.glsl} ${output[port.key]};');
    if (node.defId == 'uniform_float') {
      final name = getShaderUniformName(node);
      uniforms.add('uniform float $name;');
      body.add('\t${output['value']} = $name;');
    } else if (node.defId == 'uniform_vec2') {
      final name = getShaderUniformName(node);
      uniforms.add('uniform vec2 $name;');
      body.add('\t${output['value']} = $name;');
    } else if (node.defId == 'uniform_vec3') {
      final name = getShaderUniformName(node);
      uniforms.add('uniform vec3 $name;');
      body.add('\t${output['value']} = $name;');
    } else if (node.defId == 'float_const') {
      body.add('\t${output['value']} = ${_nodeValue(node, '1.0')};');
    } else if (node.defId == 'vec3_const') {
      body.add(
        '\t${output['value']} = ${_nodeValue(node, 'vec3(1.0, 1.0, 1.0)')};',
      );
    } else if (node.defId == 'color_ramp' && _customRamp(node)) {
      body.addAll(_compileRamp(node, input, output).map((line) => '\t$line'));
    } else {
      body.addAll(
        _compileNode(node.defId, input, output).map((line) => '\t$line'),
      );
    }
    body.add('');
  }
  return ShaderGraphCompileResult(
    glsl:
        '''precision mediump float;
uniform vec2 u_resolution;
uniform float u_time;
uniform vec3 u_accent;
uniform vec3 u_secondary;
uniform float u_intensity;
uniform float u_speed;
uniform vec3 u_camera_position;
uniform vec3 u_camera_target;
uniform vec2 u_mouse;
${uniforms.join('\n')}

$_shaderNoiseGlsl

void main() {
${body.join('\n')}
}
''',
    errors: const [],
    warnings: warnings,
  );
}

String _nodeValue(ShaderNodeInstance node, String fallback) {
  final value = node.inputDefaults['value'];
  if (value is num && value.isFinite) return '$value';
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? fallback : text;
}

List<String> _compileNode(
  String id,
  Map<String, String> i,
  Map<String, String> o,
) {
  String a(String key) => i[key] ?? '0.0';
  String z(String key) => o[key] ?? 'v_missing_$key';
  return switch (id) {
    'uv' => ['${z('uv')} = gl_FragCoord.xy / u_resolution;'],
    'time' => ['${z('t')} = u_time;'],
    'resolution' => ['${z('res')} = u_resolution;'],
    'intensity' => ['${z('value')} = u_intensity;'],
    'speed' => ['${z('value')} = u_speed;'],
    'accent_color' => ['${z('color')} = u_accent;'],
    'secondary_color' => ['${z('color')} = u_secondary;'],
    'camera_position' => ['${z('position')} = u_camera_position;'],
    'camera_target' => ['${z('target')} = u_camera_target;'],
    'mouse_position' => ['${z('mouse')} = u_mouse;'],
    'add' => ['${z('result')} = ${a('a')} + ${a('b')};'],
    'subtract' => ['${z('result')} = ${a('a')} - ${a('b')};'],
    'multiply' => ['${z('result')} = ${a('a')} * ${a('b')};'],
    'divide' => ['${z('result')} = ${a('a')} / max(${a('b')}, 0.0001);'],
    'sin' => ['${z('result')} = sin(${a('x')});'],
    'cos' => ['${z('result')} = cos(${a('x')});'],
    'abs' => ['${z('result')} = abs(${a('x')});'],
    'fract' => ['${z('result')} = fract(${a('x')});'],
    'smoothstep' => [
      '${z('result')} = smoothstep(${a('edge0')}, ${a('edge1')}, ${a('x')});',
    ],
    'clamp' => ['${z('result')} = clamp(${a('x')}, ${a('lo')}, ${a('hi')});'],
    'mix_float' => ['${z('result')} = mix(${a('a')}, ${a('b')}, ${a('t')});'],
    'remap_float' => [
      '${z('result')} = mix(${a('outMin')}, ${a('outMax')}, clamp((${a('value')} - ${a('inMin')}) / max(${a('inMax')} - ${a('inMin')}, 0.0001), 0.0, 1.0));',
    ],
    'bias_gain' => [
      '${z('result')} = sr_bias_gain(${a('value')}, ${a('bias')}, ${a('gain')});',
    ],
    'posterize' => [
      '${z('result')} = floor(clamp(${a('value')}, 0.0, 1.0) * max(${a('steps')} - 1.0, 1.0)) / max(${a('steps')} - 1.0, 1.0);',
    ],
    'wave' => [
      '${z('result')} = 0.5 + 0.5 * sin(${a('x')} * ${a('frequency')} + ${a('time')} * ${a('speed')});',
    ],
    'value_noise' => [
      '${z('value')} = sr_value_noise(${a('uv')} * ${a('scale')} + vec2(${a('seed')}));',
    ],
    'perlin_noise' => [
      '${z('value')} = clamp(0.5 + 0.5 * sr_perlin_noise(${a('uv')} * ${a('scale')} + vec2(${a('seed')})), 0.0, 1.0);',
    ],
    'fbm_noise' => [
      '${z('value')} = sr_fbm(${a('uv')} * ${a('scale')} + vec2(${a('seed')}), ${a('octaves')}, ${a('lacunarity')}, ${a('gain')});',
    ],
    'ridged_fbm_noise' => [
      '${z('value')} = sr_ridged_fbm(${a('uv')} * ${a('scale')} + vec2(${a('seed')}), ${a('octaves')}, ${a('lacunarity')}, ${a('gain')});',
    ],
    'turbulence_noise' => [
      '${z('value')} = sr_turbulence(${a('uv')} * ${a('scale')} + vec2(${a('seed')}), ${a('octaves')}, ${a('lacunarity')}, ${a('gain')});',
    ],
    'voronoi_noise' => [
      '${z('distance')} = sr_voronoi(${a('uv')} * ${a('scale')} + vec2(${a('seed')}), ${a('jitter')});',
    ],
    'cellular_f1_f2' => [
      'vec2 ${z('f1')}_cell = sr_cellular(${a('uv')} * ${a('scale')} + vec2(${a('seed')}), ${a('jitter')});',
      '${z('f1')} = ${z('f1')}_cell.x;',
      '${z('f2')} = ${z('f1')}_cell.y;',
      '${z('edge')} = clamp(${z('f2')} - ${z('f1')}, 0.0, 1.0);',
    ],
    'curl_noise' => [
      '${z('curl')} = sr_curl_noise(${a('uv')} * ${a('scale')} + vec2(${a('seed')}), ${a('epsilon')}) * ${a('strength')};',
      '${z('uv')} = ${a('uv')} + ${z('curl')};',
    ],
    'domain_warp' => [
      '${z('uv')} = sr_domain_warp(${a('uv')} * ${a('scale')} + vec2(${a('seed')}), ${a('strength')});',
      '${z('value')} = sr_fbm(${z('uv')}, 5.0, 2.0, 0.5);',
    ],
    'terrain_height' => [
      '${z('height')} = (${a('base')} + ${a('detail')} * ${a('detailStrength')}) * ${a('amplitude')} + ${a('offset')};',
    ],
    'height_remap' => [
      '${z('height')} = pow(clamp((${a('height')} - ${a('min')}) / max(${a('max')} - ${a('min')}, 0.0001), 0.0, 1.0), max(${a('power')}, 0.0001));',
    ],
    'normal_from_height' => [
      '${z('normal')} = normalize(vec3((${a('center')} - ${a('right')}) * ${a('strength')}, (${a('center')} - ${a('up')}) * ${a('strength')}, max(${a('spacing')}, 0.0001)));',
    ],
    'slope_mask' => [
      '${z('mask')} = smoothstep(${a('minSlope')}, ${a('maxSlope')}, 1.0 - clamp(${a('normal')}.z, 0.0, 1.0));',
    ],
    'curvature_mask' => [
      '${z('mask')} = clamp(abs((${a('left')} + ${a('right')} + ${a('down')} + ${a('up')}) - 4.0 * ${a('center')}) * ${a('strength')}, 0.0, 1.0);',
    ],
    'thermal_erosion' => [
      '${z('height')} = ${a('height')} - max(${a('slope')} - ${a('threshold')}, 0.0) * ${a('amount')};',
    ],
    'sampled_terrain_height' => [
      '${z('height')} = sr_terrain_height_sample(${a('uv')}, ${a('scale')}, ${a('warp')}, ${a('detail')}, ${a('amplitude')}, ${a('seed')});',
    ],
    'sampled_terrain_normal' => [
      '${z('height')} = sr_terrain_height_sample(${a('uv')}, ${a('scale')}, ${a('warp')}, ${a('detail')}, ${a('amplitude')}, ${a('seed')});',
      'float ${z('normal')}_right = sr_terrain_height_sample(${a('uv')} + vec2(${a('spacing')}, 0.0), ${a('scale')}, ${a('warp')}, ${a('detail')}, ${a('amplitude')}, ${a('seed')});',
      'float ${z('normal')}_up = sr_terrain_height_sample(${a('uv')} + vec2(0.0, ${a('spacing')}), ${a('scale')}, ${a('warp')}, ${a('detail')}, ${a('amplitude')}, ${a('seed')});',
      '${z('normal')} = normalize(vec3((${z('height')} - ${z('normal')}_right) * ${a('strength')}, (${z('height')} - ${z('normal')}_up) * ${a('strength')}, max(${a('spacing')}, 0.0001)));',
      '${z('slope')} = 1.0 - clamp(${z('normal')}.z, 0.0, 1.0);',
    ],
    'vec2_compose' => ['${z('result')} = vec2(${a('x')}, ${a('y')});'],
    'tile_uv' => ['${z('uv')} = fract(${a('uv')} * ${a('scale')});'],
    'rotate_uv' => [
      'vec2 ${z('uv')}_centered = ${a('uv')} - 0.5;',
      'float ${z('uv')}_s = sin(${a('angle')});',
      'float ${z('uv')}_c = cos(${a('angle')});',
      '${z('uv')} = mat2(${z('uv')}_c, -${z('uv')}_s, ${z('uv')}_s, ${z('uv')}_c) * ${z('uv')}_centered + 0.5;',
    ],
    'vec2_split' => ['${z('x')} = ${a('v')}.x;', '${z('y')} = ${a('v')}.y;'],
    'vec3_compose' => [
      '${z('result')} = vec3(${a('x')}, ${a('y')}, ${a('z')});',
    ],
    'vec3_split' => [
      '${z('x')} = ${a('v')}.x;',
      '${z('y')} = ${a('v')}.y;',
      '${z('z')} = ${a('v')}.z;',
    ],
    'length' => ['${z('result')} = length(${a('v')});'],
    'distance' => ['${z('result')} = distance(${a('a')}, ${a('b')});'],
    'dot' => ['${z('result')} = dot(${a('a')}, ${a('b')});'],
    'mix_color' => ['${z('result')} = mix(${a('a')}, ${a('b')}, ${a('t')});'],
    'gradient_color' => [
      '${z('color')} = mix(${a('a')}, ${a('b')}, clamp(${a('factor')}, 0.0, 1.0));',
    ],
    'color_ramp' => [
      'float ${z('color')}_f = clamp(${a('factor')}, 0.0, 1.0);',
      'float ${z('color')}_m = smoothstep(${a('midpoint')} - ${a('softness')}, ${a('midpoint')} + ${a('softness')}, ${z('color')}_f);',
      '${z('color')} = mix(mix(${a('low')}, ${a('mid')}, smoothstep(0.0, max(${a('midpoint')}, 0.0001), ${z('color')}_f)), ${a('high')}, ${z('color')}_m);',
    ],
    'biome_mask' => [
      'float ${z('mask')}_low = smoothstep(${a('minHeight')} - ${a('softness')}, ${a('minHeight')} + ${a('softness')}, ${a('height')});',
      'float ${z('mask')}_high = 1.0 - smoothstep(${a('maxHeight')} - ${a('softness')}, ${a('maxHeight')} + ${a('softness')}, ${a('height')});',
      'float ${z('mask')}_slope = 1.0 - smoothstep(${a('maxSlope')} - ${a('softness')}, ${a('maxSlope')} + ${a('softness')}, ${a('slope')});',
      '${z('mask')} = clamp(${z('mask')}_low * ${z('mask')}_high * ${z('mask')}_slope, 0.0, 1.0);',
    ],
    'altitude_bands' => [
      '${z('grassMask')} = 1.0 - smoothstep(${a('rockLine')} - ${a('softness')}, ${a('rockLine')} + ${a('softness')}, ${a('height')});',
      '${z('rockMask')} = smoothstep(${a('grassLine')} - ${a('softness')}, ${a('grassLine')} + ${a('softness')}, ${a('height')}) * (1.0 - smoothstep(${a('snowLine')} - ${a('softness')}, ${a('snowLine')} + ${a('softness')}, ${a('height')}));',
      '${z('snowMask')} = smoothstep(${a('snowLine')} - ${a('softness')}, ${a('snowLine')} + ${a('softness')}, ${a('height')});',
      '${z('color')} = mix(mix(${a('grass')}, ${a('rock')}, clamp(${z('rockMask')}, 0.0, 1.0)), ${a('snow')}, clamp(${z('snowMask')}, 0.0, 1.0));',
    ],
    'mask_blend_color' => [
      '${z('color')} = mix(${a('base')}, ${a('detail')}, clamp(${a('mask')}, 0.0, 1.0));',
    ],
    'sun_direction' => [
      'float ${z('direction')}_az = ${a('azimuth')} * 6.2831853;',
      'float ${z('direction')}_el = clamp(${a('elevation')}, 0.0, 1.0) * 1.5707963;',
      '${z('direction')} = normalize(vec3(cos(${z('direction')}_az) * cos(${z('direction')}_el), sin(${z('direction')}_az) * cos(${z('direction')}_el), sin(${z('direction')}_el)));',
    ],
    'diffuse_lighting' => [
      '${z('light')} = max(dot(normalize(${a('normal')}), normalize(${a('lightDir')})), 0.0) * ${a('intensity')};',
      '${z('color')} = ${a('color')} * (${a('ambient')} + ${z('light')});',
    ],
    'specular_lighting' => [
      'vec3 ${z('specular')}_halfDir = normalize(normalize(${a('lightDir')}) + normalize(${a('viewDir')}));',
      '${z('specular')} = pow(max(dot(normalize(${a('normal')}), ${z('specular')}_halfDir), 0.0), max(${a('shininess')}, 1.0)) * ${a('intensity')};',
    ],
    'ambient_light' => [
      '${z('color')} = ${a('color')} + ${a('ambientColor')} * ${a('intensity')};',
    ],
    'fog' => [
      '${z('color')} = mix(${a('color')}, ${a('fogColor')}, clamp(1.0 - exp(-max(${a('depth')}, 0.0) * ${a('density')}), 0.0, 1.0));',
    ],
    'simple_shadow' => [
      '${z('shadow')} = smoothstep(-${a('softness')}, ${a('softness')}, dot(normalize(${a('normal')}), normalize(${a('lightDir')})));',
    ],
    'ambient_occlusion' => [
      '${z('ao')} = clamp(1.0 - (${a('curvature')} * 0.65 + ${a('slope')} * 0.35) * ${a('strength')}, 0.0, 1.0);',
    ],
    'normal_strength' => [
      '${z('normal')} = normalize(vec3(${a('normal')}.xy * ${a('strength')}, max(${a('normal')}.z, 0.0001)));',
    ],
    'triplanar_coords' => [
      '${z('xUV')} = ${a('position')}.yz * ${a('scale')};',
      '${z('yUV')} = ${a('position')}.xz * ${a('scale')};',
      '${z('zUV')} = ${a('position')}.xy * ${a('scale')};',
      '${z('weights')} = pow(abs(normalize(${a('normal')})), vec3(max(${a('sharpness')}, 0.0001)));',
      '${z('weights')} /= max(dot(${z('weights')}, vec3(1.0)), 0.0001);',
    ],
    'layer_mask' => [
      'float ${z('mask')}_height = smoothstep(${a('heightMin')} - ${a('softness')}, ${a('heightMin')} + ${a('softness')}, ${a('height')}) * (1.0 - smoothstep(${a('heightMax')} - ${a('softness')}, ${a('heightMax')} + ${a('softness')}, ${a('height')}));',
      'float ${z('mask')}_slope = 1.0 - smoothstep(${a('slopeMax')} - ${a('softness')}, ${a('slopeMax')} + ${a('softness')}, ${a('slope')});',
      '${z('mask')} = clamp(${z('mask')}_height * ${z('mask')}_slope + (${a('noise')} - 0.5) * ${a('noiseAmount')}, 0.0, 1.0);',
    ],
    'fresnel' => [
      '${z('factor')} = clamp(${a('bias')} + ${a('scale')} * pow(1.0 - max(dot(normalize(${a('normal')}), normalize(${a('viewDir')})), 0.0), max(${a('power')}, 0.0001)), 0.0, 1.0);',
    ],
    'rough_specular' => [
      'vec3 ${z('specular')}_halfDir = normalize(normalize(${a('lightDir')}) + normalize(${a('viewDir')}));',
      'float ${z('specular')}_power = mix(96.0, 4.0, clamp(${a('roughness')}, 0.0, 1.0));',
      '${z('specular')} = pow(max(dot(normalize(${a('normal')}), ${z('specular')}_halfDir), 0.0), ${z('specular')}_power) * ${a('intensity')};',
    ],
    'camera_ray' => [
      '${z('origin')} = ${a('position')};',
      'vec3 ${z('direction')}_forward = normalize(${a('target')} - ${a('position')});',
      'vec3 ${z('direction')}_right = normalize(cross(${z('direction')}_forward, vec3(0.0, 1.0, 0.0)));',
      'vec3 ${z('direction')}_up = normalize(cross(${z('direction')}_right, ${z('direction')}_forward));',
      'vec2 ${z('direction')}_screen = (${a('uv')} * 2.0 - 1.0) * vec2(${a('aspect')}, 1.0) * tan(${a('fov')} * 0.5);',
      '${z('direction')} = normalize(${z('direction')}_forward + ${z('direction')}_right * ${z('direction')}_screen.x + ${z('direction')}_up * ${z('direction')}_screen.y);',
    ],
    'ray_point' => [
      '${z('point')} = ${a('origin')} + normalize(${a('direction')}) * ${a('depth')};',
    ],
    'sdf_sphere' => [
      '${z('distance')} = length(${a('point')} - ${a('center')}) - ${a('radius')};',
    ],
    'sdf_plane' => ['${z('distance')} = ${a('point')}.y - ${a('height')};'],
    'raymarch_sphere' => [
      '${z('depth')} = 0.0;',
      '${z('hit')} = 0.0;',
      'for (int ${z('depth')}_i = 0; ${z('depth')}_i < 96; ${z('depth')}_i++) {',
      '\tif (float(${z('depth')}_i) >= ${a('maxSteps')}) break;',
      '\tvec3 ${z('depth')}_p = ${a('origin')} + normalize(${a('direction')}) * ${z('depth')};',
      '\tfloat ${z('depth')}_d = length(${z('depth')}_p - ${a('center')}) - ${a('radius')};',
      '\tif (${z('depth')}_d < 0.001) { ${z('hit')} = 1.0; break; }',
      '\t${z('depth')} += ${z('depth')}_d;',
      '\tif (${z('depth')} > ${a('maxDistance')}) break;',
      '}',
    ],
    'depth_fade' => [
      '${z('factor')} = smoothstep(${a('near')}, max(${a('far')}, ${a('near')} + 0.0001), ${a('depth')});',
    ],
    'reroute_float' ||
    'reroute_vec2' ||
    'reroute_vec3' => ['${z('value')} = ${a('value')};'],
    'fragment_output' => ['gl_FragColor = vec4(${a('color')}, ${a('alpha')});'],
    _ => ['// Unsupported node body: $id'],
  };
}

bool _customRamp(ShaderNodeInstance node) {
  final value = node.inputDefaults['rampStops'];
  if (value is List) return value.length >= 2;
  if (value is String && value.trim().isNotEmpty) {
    try {
      final parsed = jsonDecode(value);
      return parsed is List && parsed.length >= 2;
    } on FormatException {
      return false;
    }
  }
  return false;
}

List<String> _compileRamp(
  ShaderNodeInstance node,
  Map<String, String> i,
  Map<String, String> o,
) {
  final stops = _normalizeRamp(node.inputDefaults['rampStops']);
  final factor = i['factor'] ?? '0.5';
  final color = o['color']!;
  final lines = <String>[
    'float ${color}_f = clamp($factor, 0.0, 1.0);',
    'vec3 ${color}_ramp = ${stops.first['color']};',
  ];
  for (var index = 1; index < stops.length; index++) {
    final previous = stops[index - 1];
    final current = stops[index];
    lines.add(
      '${color}_ramp = mix(${color}_ramp, ${current['color']}, smoothstep(${_float(previous['offset'] as double)}, max(${_float(current['offset'] as double)}, ${_float(previous['offset'] as double)} + 0.0001), ${color}_f));',
    );
  }
  lines.add('$color = ${color}_ramp;');
  return lines;
}

List<Map<String, dynamic>> _normalizeRamp(dynamic value) {
  dynamic source = value;
  if (source is String) {
    try {
      source = jsonDecode(source);
    } on FormatException {
      source = const [];
    }
  }
  final stops = source is List
      ? source.whereType<Map>().map((item) {
          final offset = item['offset'];
          final color = item['color']?.toString() ?? '';
          return {
            'offset': offset is num ? offset.toDouble().clamp(0, 1) : 0.0,
            'color': _vec3Literal(color),
          };
        }).toList()
      : <Map<String, dynamic>>[];
  if (stops.length < 2)
    return defaultShaderColorRampStops.map(Map<String, dynamic>.from).toList();
  stops.sort(
    (a, b) => (a['offset'] as double).compareTo(b['offset'] as double),
  );
  return stops;
}

String _vec3Literal(String value) {
  final hex = RegExp(
    r'^#?([0-9a-f]{3}|[0-9a-f]{6})$',
    caseSensitive: false,
  ).firstMatch(value.trim());
  if (hex != null) {
    var source = hex.group(1)!;
    if (source.length == 3)
      source = source.split('').map((char) => '$char$char').join();
    final parsed = int.parse(source, radix: 16);
    return 'vec3(${_float(((parsed >> 16) & 255) / 255)}, ${_float(((parsed >> 8) & 255) / 255)}, ${_float((parsed & 255) / 255)})';
  }
  final source =
      RegExp(r'vec\d\s*\(([^)]*)\)').firstMatch(value)?.group(1) ?? value;
  final parts = RegExp(r'[-+]?\d*\.?\d+')
      .allMatches(source)
      .map((match) => double.tryParse(match.group(0)!) ?? 1)
      .toList();
  return 'vec3(${_float(parts.elementAtOrNull(0) ?? 1)}, ${_float(parts.elementAtOrNull(1) ?? 1)}, ${_float(parts.elementAtOrNull(2) ?? 1)})';
}

List<double> _parseVector(String value, int length, List<double> fallback) {
  final source =
      RegExp(r'vec\d\s*\(([^)]*)\)').firstMatch(value)?.group(1) ?? value;
  final parts = RegExp(r'[-+]?\d*\.?\d+')
      .allMatches(source)
      .map((match) => double.tryParse(match.group(0)!) ?? 0)
      .toList();
  return [
    for (var index = 0; index < length; index++)
      parts.elementAtOrNull(index) ?? fallback[index],
  ];
}

String _float(double value) {
  if (!value.isFinite) return '0';
  final rounded = double.parse(value.toStringAsFixed(4));
  return rounded.toString();
}

const _shaderNoiseGlsl = r'''float sr_hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec2 sr_hash22(vec2 p) {
	float n = sr_hash21(p);
	return fract(vec2(n, n + 0.37) * vec2(269.5, 183.3));
}

float sr_value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = sr_hash21(i);
	float b = sr_hash21(i + vec2(1.0, 0.0));
	float c = sr_hash21(i + vec2(0.0, 1.0));
	float d = sr_hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float sr_perlin_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	vec2 ga = normalize(sr_hash22(i) * 2.0 - 1.0);
	vec2 gb = normalize(sr_hash22(i + vec2(1.0, 0.0)) * 2.0 - 1.0);
	vec2 gc = normalize(sr_hash22(i + vec2(0.0, 1.0)) * 2.0 - 1.0);
	vec2 gd = normalize(sr_hash22(i + vec2(1.0, 1.0)) * 2.0 - 1.0);
	float a = dot(ga, f);
	float b = dot(gb, f - vec2(1.0, 0.0));
	float c = dot(gc, f - vec2(0.0, 1.0));
	float d = dot(gd, f - vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float sr_fbm(vec2 p, float octaves, float lacunarity, float gain) {
	float value = 0.0;
	float amplitude = 0.5;
	float norm = 0.0;
	for (int i = 0; i < 8; i++) {
		if (float(i) >= octaves) break;
		value += amplitude * sr_value_noise(p);
		norm += amplitude;
		p *= lacunarity;
		amplitude *= gain;
	}
	return norm > 0.0 ? value / norm : 0.0;
}

float sr_ridged_fbm(vec2 p, float octaves, float lacunarity, float gain) {
	float value = 0.0;
	float amplitude = 0.5;
	float norm = 0.0;
	for (int i = 0; i < 8; i++) {
		if (float(i) >= octaves) break;
		float signal = 1.0 - abs(sr_perlin_noise(p));
		signal *= signal;
		value += signal * amplitude;
		norm += amplitude;
		p *= lacunarity;
		amplitude *= gain;
	}
	return norm > 0.0 ? clamp(value / norm, 0.0, 1.0) : 0.0;
}

float sr_turbulence(vec2 p, float octaves, float lacunarity, float gain) {
	float value = 0.0;
	float amplitude = 0.5;
	float norm = 0.0;
	for (int i = 0; i < 8; i++) {
		if (float(i) >= octaves) break;
		value += abs(sr_perlin_noise(p)) * amplitude;
		norm += amplitude;
		p *= lacunarity;
		amplitude *= gain;
	}
	return norm > 0.0 ? clamp(value / norm, 0.0, 1.0) : 0.0;
}

float sr_voronoi(vec2 p, float jitter) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float nearest = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 cell = vec2(float(x), float(y));
			vec2 point = cell + mix(vec2(0.5), sr_hash22(i + cell), clamp(jitter, 0.0, 1.0)) - f;
			nearest = min(nearest, dot(point, point));
		}
	}
	return clamp(sqrt(nearest), 0.0, 1.0);
}

vec2 sr_cellular(vec2 p, float jitter) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 cell = vec2(float(x), float(y));
			vec2 point = cell + mix(vec2(0.5), sr_hash22(i + cell), clamp(jitter, 0.0, 1.0)) - f;
			float d = dot(point, point);
			if (d < f1) { f2 = f1; f1 = d; } else if (d < f2) { f2 = d; }
		}
	}
	return clamp(sqrt(vec2(f1, f2)), 0.0, 1.0);
}

vec2 sr_curl_noise(vec2 p, float epsilon) {
	float e = max(epsilon, 0.0001);
	float x0 = sr_fbm(p - vec2(e, 0.0), 4.0, 2.0, 0.5);
	float x1 = sr_fbm(p + vec2(e, 0.0), 4.0, 2.0, 0.5);
	float y0 = sr_fbm(p - vec2(0.0, e), 4.0, 2.0, 0.5);
	float y1 = sr_fbm(p + vec2(0.0, e), 4.0, 2.0, 0.5);
	return normalize(vec2(y1 - y0, x0 - x1) / (2.0 * e));
}

float sr_bias(float value, float bias) {
	float b = clamp(bias, 0.001, 0.999);
	float x = clamp(value, 0.0, 1.0);
	return x / (((1.0 / b - 2.0) * (1.0 - x)) + 1.0);
}

float sr_bias_gain(float value, float bias, float gain) {
	float biased = sr_bias(value, bias);
	float g = clamp(gain, 0.001, 0.999);
	if (biased < 0.5) return sr_bias(biased * 2.0, 1.0 - g) * 0.5;
	return 1.0 - sr_bias(2.0 - biased * 2.0, 1.0 - g) * 0.5;
}

vec2 sr_domain_warp(vec2 p, float strength) {
	float x = sr_fbm(p + vec2(17.2, 9.1), 4.0, 2.0, 0.5);
	float y = sr_fbm(p + vec2(-8.3, 23.7), 4.0, 2.0, 0.5);
	return p + (vec2(x, y) * 2.0 - 1.0) * strength;
}

float sr_terrain_height_sample(vec2 uv, float scale, float warp, float detail, float amplitude, float seed) {
	vec2 p = uv * scale + vec2(seed);
	vec2 warped = sr_domain_warp(p, warp);
	float base = sr_fbm(warped, 6.0, 2.0, 0.5);
	float fine = sr_fbm(warped * 4.0 + vec2(31.7, -14.2), 4.0, 2.15, 0.45);
	return clamp((base + fine * detail) * amplitude, 0.0, 1.0);
}''';
