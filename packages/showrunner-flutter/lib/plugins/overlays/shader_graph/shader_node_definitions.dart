import 'shader_graph_model.dart';

final class ShaderNodeDefinition {
  const ShaderNodeDefinition({
    required this.id,
    required this.name,
    required this.category,
    required this.inputs,
    required this.outputs,
  });

  final String id;
  final String name;
  final String category;
  final List<ShaderPortDefinition> inputs;
  final List<ShaderPortDefinition> outputs;
}

ShaderPortDefinition _p(
  String key,
  ShaderGlslType type, [
  String? defaultValue,
  String? label,
]) => ShaderPortDefinition(
  key: key,
  label: label ?? _label(key),
  type: type,
  defaultValue: defaultValue,
);

ShaderNodeDefinition _d(
  String id,
  String name,
  String category,
  List<ShaderPortDefinition> inputs,
  List<ShaderPortDefinition> outputs,
) => ShaderNodeDefinition(
  id: id,
  name: name,
  category: category,
  inputs: inputs,
  outputs: outputs,
);

String _label(String key) => switch (key) {
  'uv' => 'UV',
  't' => 'Time',
  'res' => 'Resolution',
  'value' => 'Value',
  'color' => 'Color',
  'position' => 'Position',
  'target' => 'Target',
  'mouse' => 'Mouse',
  'result' => 'Result',
  'distance' => 'Distance',
  'normal' => 'Normal',
  'direction' => 'Direction',
  'height' => 'Height',
  'mask' => 'Mask',
  'factor' => 'Factor',
  'specular' => 'Specular',
  'shadow' => 'Shadow',
  'ao' => 'AO',
  'point' => 'Point',
  'origin' => 'Origin',
  'depth' => 'Depth',
  'hit' => 'Hit',
  'xUV' => 'X UV',
  'yUV' => 'Y UV',
  'zUV' => 'Z UV',
  'weights' => 'Weights',
  'grassMask' => 'Grass',
  'rockMask' => 'Rock',
  'snowMask' => 'Snow',
  'curl' => 'Curl',
  _ => key[0].toUpperCase() + key.substring(1),
};

final shaderNodeDefinitions = <ShaderNodeDefinition>[
  // Input
  _d('uv', 'UV Coordinates', 'Input', const [], [
    _p('uv', ShaderGlslType.vec2),
  ]),
  _d('time', 'Time', 'Input', const [], [_p('t', ShaderGlslType.float)]),
  _d('resolution', 'Resolution', 'Input', const [], [
    _p('res', ShaderGlslType.vec2),
  ]),
  _d('intensity', 'Intensity', 'Input', const [], [
    _p('value', ShaderGlslType.float, '1.0'),
  ]),
  _d('speed', 'Speed', 'Input', const [], [
    _p('value', ShaderGlslType.float, '1.0'),
  ]),
  _d('accent_color', 'Accent Color', 'Input', const [], [
    _p('color', ShaderGlslType.vec3),
  ]),
  _d('secondary_color', 'Secondary Color', 'Input', const [], [
    _p('color', ShaderGlslType.vec3),
  ]),
  _d('float_const', 'Float', 'Input', const [], [
    _p('value', ShaderGlslType.float, '1.0'),
  ]),
  _d('vec3_const', 'Color / Vec3', 'Input', const [], [
    _p('value', ShaderGlslType.vec3, 'vec3(1.0, 1.0, 1.0)'),
  ]),
  _d('uniform_float', 'Float Parameter', 'Input', const [], [
    _p('value', ShaderGlslType.float, '1.0'),
  ]),
  _d('uniform_vec2', 'Vec2 Parameter', 'Input', const [], [
    _p('value', ShaderGlslType.vec2, 'vec2(0.0, 0.0)'),
  ]),
  _d('uniform_vec3', 'Color Parameter', 'Input', const [], [
    _p('value', ShaderGlslType.vec3, 'vec3(1.0, 1.0, 1.0)'),
  ]),
  _d('camera_position', 'Camera Position', 'Input', const [], [
    _p('position', ShaderGlslType.vec3, 'vec3(0.0, 0.0, 2.5)'),
  ]),
  _d('camera_target', 'Camera Target', 'Input', const [], [
    _p('target', ShaderGlslType.vec3, 'vec3(0.0, 0.0, 0.0)'),
  ]),
  _d('mouse_position', 'Mouse Position', 'Input', const [], [
    _p('mouse', ShaderGlslType.vec2, 'vec2(0.0)'),
  ]),

  // Math
  _d(
    'add',
    'Add',
    'Math',
    [
      _p('a', ShaderGlslType.float, '0.0'),
      _p('b', ShaderGlslType.float, '0.0'),
    ],
    [_p('result', ShaderGlslType.float)],
  ),
  _d(
    'subtract',
    'Subtract',
    'Math',
    [
      _p('a', ShaderGlslType.float, '0.0'),
      _p('b', ShaderGlslType.float, '0.0'),
    ],
    [_p('result', ShaderGlslType.float)],
  ),
  _d(
    'multiply',
    'Multiply',
    'Math',
    [
      _p('a', ShaderGlslType.float, '1.0'),
      _p('b', ShaderGlslType.float, '1.0'),
    ],
    [_p('result', ShaderGlslType.float)],
  ),
  _d(
    'divide',
    'Divide',
    'Math',
    [
      _p('a', ShaderGlslType.float, '1.0'),
      _p('b', ShaderGlslType.float, '1.0'),
    ],
    [_p('result', ShaderGlslType.float)],
  ),
  _d(
    'sin',
    'Sin',
    'Math',
    [_p('x', ShaderGlslType.float, '0.0')],
    [_p('result', ShaderGlslType.float)],
  ),
  _d(
    'cos',
    'Cos',
    'Math',
    [_p('x', ShaderGlslType.float, '0.0')],
    [_p('result', ShaderGlslType.float)],
  ),
  _d(
    'abs',
    'Abs',
    'Math',
    [_p('x', ShaderGlslType.float, '0.0')],
    [_p('result', ShaderGlslType.float)],
  ),
  _d(
    'fract',
    'Fract',
    'Math',
    [_p('x', ShaderGlslType.float, '0.0')],
    [_p('result', ShaderGlslType.float)],
  ),
  _d(
    'smoothstep',
    'Smoothstep',
    'Math',
    [
      _p('edge0', ShaderGlslType.float, '0.0'),
      _p('edge1', ShaderGlslType.float, '1.0'),
      _p('x', ShaderGlslType.float, '0.5'),
    ],
    [_p('result', ShaderGlslType.float)],
  ),
  _d(
    'clamp',
    'Clamp',
    'Math',
    [
      _p('x', ShaderGlslType.float, '0.0'),
      _p('lo', ShaderGlslType.float, '0.0'),
      _p('hi', ShaderGlslType.float, '1.0'),
    ],
    [_p('result', ShaderGlslType.float)],
  ),
  _d(
    'mix_float',
    'Mix (Lerp)',
    'Math',
    [
      _p('a', ShaderGlslType.float, '0.0'),
      _p('b', ShaderGlslType.float, '1.0'),
      _p('t', ShaderGlslType.float, '0.5'),
    ],
    [_p('result', ShaderGlslType.float)],
  ),
  _d(
    'remap_float',
    'Remap',
    'Math',
    [
      _p('value', ShaderGlslType.float, '0.0'),
      _p('inMin', ShaderGlslType.float, '0.0'),
      _p('inMax', ShaderGlslType.float, '1.0'),
      _p('outMin', ShaderGlslType.float, '0.0'),
      _p('outMax', ShaderGlslType.float, '1.0'),
    ],
    [_p('result', ShaderGlslType.float)],
  ),
  _d(
    'bias_gain',
    'Bias / Gain',
    'Math',
    [
      _p('value', ShaderGlslType.float, '0.5'),
      _p('bias', ShaderGlslType.float, '0.5'),
      _p('gain', ShaderGlslType.float, '0.5'),
    ],
    [_p('result', ShaderGlslType.float)],
  ),
  _d(
    'posterize',
    'Posterize',
    'Math',
    [
      _p('value', ShaderGlslType.float, '0.5'),
      _p('steps', ShaderGlslType.float, '5.0'),
    ],
    [_p('result', ShaderGlslType.float)],
  ),
  _d(
    'wave',
    'Wave',
    'Math',
    [
      _p('x', ShaderGlslType.float, '0.0'),
      _p('time', ShaderGlslType.float, '0.0'),
      _p('frequency', ShaderGlslType.float, '6.0'),
      _p('speed', ShaderGlslType.float, '1.0'),
    ],
    [_p('result', ShaderGlslType.float, null, 'Wave')],
  ),

  // Noise
  _d(
    'value_noise',
    'Value Noise',
    'Noise',
    [
      _p('uv', ShaderGlslType.vec2, 'vec2(0.0)'),
      _p('scale', ShaderGlslType.float, '6.0'),
      _p('seed', ShaderGlslType.float, '0.0'),
    ],
    [_p('value', ShaderGlslType.float)],
  ),
  _d(
    'perlin_noise',
    'Perlin Noise',
    'Noise',
    [
      _p('uv', ShaderGlslType.vec2, 'vec2(0.0)'),
      _p('scale', ShaderGlslType.float, '6.0'),
      _p('seed', ShaderGlslType.float, '0.0'),
    ],
    [_p('value', ShaderGlslType.float)],
  ),
  _d(
    'fbm_noise',
    'FBM Noise',
    'Noise',
    [
      _p('uv', ShaderGlslType.vec2, 'vec2(0.0)'),
      _p('scale', ShaderGlslType.float, '4.0'),
      _p('octaves', ShaderGlslType.float, '5.0'),
      _p('lacunarity', ShaderGlslType.float, '2.0'),
      _p('gain', ShaderGlslType.float, '0.5'),
      _p('seed', ShaderGlslType.float, '0.0'),
    ],
    [_p('value', ShaderGlslType.float)],
  ),
  _d(
    'ridged_fbm_noise',
    'Ridged FBM',
    'Noise',
    [
      _p('uv', ShaderGlslType.vec2, 'vec2(0.0)'),
      _p('scale', ShaderGlslType.float, '4.0'),
      _p('octaves', ShaderGlslType.float, '5.0'),
      _p('lacunarity', ShaderGlslType.float, '2.0'),
      _p('gain', ShaderGlslType.float, '0.5'),
      _p('seed', ShaderGlslType.float, '0.0'),
    ],
    [_p('value', ShaderGlslType.float)],
  ),
  _d(
    'turbulence_noise',
    'Turbulence',
    'Noise',
    [
      _p('uv', ShaderGlslType.vec2, 'vec2(0.0)'),
      _p('scale', ShaderGlslType.float, '4.0'),
      _p('octaves', ShaderGlslType.float, '5.0'),
      _p('lacunarity', ShaderGlslType.float, '2.0'),
      _p('gain', ShaderGlslType.float, '0.5'),
      _p('seed', ShaderGlslType.float, '0.0'),
    ],
    [_p('value', ShaderGlslType.float)],
  ),
  _d(
    'voronoi_noise',
    'Voronoi',
    'Noise',
    [
      _p('uv', ShaderGlslType.vec2, 'vec2(0.0)'),
      _p('scale', ShaderGlslType.float, '8.0'),
      _p('jitter', ShaderGlslType.float, '0.8'),
      _p('seed', ShaderGlslType.float, '0.0'),
    ],
    [_p('distance', ShaderGlslType.float)],
  ),
  _d(
    'cellular_f1_f2',
    'Cellular F1 / F2',
    'Noise',
    [
      _p('uv', ShaderGlslType.vec2, 'vec2(0.0)'),
      _p('scale', ShaderGlslType.float, '8.0'),
      _p('jitter', ShaderGlslType.float, '0.8'),
      _p('seed', ShaderGlslType.float, '0.0'),
    ],
    [
      _p('f1', ShaderGlslType.float),
      _p('f2', ShaderGlslType.float),
      _p('edge', ShaderGlslType.float),
    ],
  ),
  _d(
    'curl_noise',
    'Curl Noise',
    'Noise',
    [
      _p('uv', ShaderGlslType.vec2, 'vec2(0.0)'),
      _p('scale', ShaderGlslType.float, '3.0'),
      _p('strength', ShaderGlslType.float, '0.2'),
      _p('epsilon', ShaderGlslType.float, '0.01'),
      _p('seed', ShaderGlslType.float, '0.0'),
    ],
    [
      _p('curl', ShaderGlslType.vec2),
      _p('uv', ShaderGlslType.vec2, null, 'Warped UV'),
    ],
  ),
  _d(
    'domain_warp',
    'Domain Warp',
    'Noise',
    [
      _p('uv', ShaderGlslType.vec2, 'vec2(0.0)'),
      _p('scale', ShaderGlslType.float, '3.0'),
      _p('strength', ShaderGlslType.float, '0.25'),
      _p('seed', ShaderGlslType.float, '0.0'),
    ],
    [
      _p('uv', ShaderGlslType.vec2, null, 'Warped UV'),
      _p('value', ShaderGlslType.float),
    ],
  ),

  // Terrain
  _d(
    'terrain_height',
    'Terrain Height',
    'Terrain',
    [
      _p('base', ShaderGlslType.float, '0.0'),
      _p('detail', ShaderGlslType.float, '0.0'),
      _p('amplitude', ShaderGlslType.float, '1.0'),
      _p('detailStrength', ShaderGlslType.float, '0.25'),
      _p('offset', ShaderGlslType.float, '0.0'),
    ],
    [_p('height', ShaderGlslType.float)],
  ),
  _d(
    'height_remap',
    'Remap Height',
    'Terrain',
    [
      _p('height', ShaderGlslType.float, '0.0'),
      _p('min', ShaderGlslType.float, '0.0'),
      _p('max', ShaderGlslType.float, '1.0'),
      _p('power', ShaderGlslType.float, '1.0'),
    ],
    [_p('height', ShaderGlslType.float)],
  ),
  _d(
    'normal_from_height',
    'Normal From Height',
    'Terrain',
    [
      _p('center', ShaderGlslType.float, '0.0'),
      _p('right', ShaderGlslType.float, '0.0'),
      _p('up', ShaderGlslType.float, '0.0'),
      _p('spacing', ShaderGlslType.float, '0.01'),
      _p('strength', ShaderGlslType.float, '1.0'),
    ],
    [_p('normal', ShaderGlslType.vec3)],
  ),
  _d(
    'slope_mask',
    'Slope Mask',
    'Terrain',
    [
      _p('normal', ShaderGlslType.vec3, 'vec3(0.0, 0.0, 1.0)'),
      _p('minSlope', ShaderGlslType.float, '0.2'),
      _p('maxSlope', ShaderGlslType.float, '0.8'),
    ],
    [_p('mask', ShaderGlslType.float)],
  ),
  _d(
    'curvature_mask',
    'Curvature Mask',
    'Terrain',
    [
      _p('center', ShaderGlslType.float, '0.0'),
      _p('left', ShaderGlslType.float, '0.0'),
      _p('right', ShaderGlslType.float, '0.0'),
      _p('down', ShaderGlslType.float, '0.0'),
      _p('up', ShaderGlslType.float, '0.0'),
      _p('strength', ShaderGlslType.float, '2.0'),
    ],
    [_p('mask', ShaderGlslType.float)],
  ),
  _d(
    'thermal_erosion',
    'Thermal Erosion',
    'Terrain',
    [
      _p('height', ShaderGlslType.float, '0.0'),
      _p('slope', ShaderGlslType.float, '0.0'),
      _p('threshold', ShaderGlslType.float, '0.35'),
      _p('amount', ShaderGlslType.float, '0.08'),
    ],
    [_p('height', ShaderGlslType.float)],
  ),
  _d(
    'sampled_terrain_height',
    'Sampled Terrain Height',
    'Terrain',
    [
      _p('uv', ShaderGlslType.vec2, 'vec2(0.0)'),
      _p('scale', ShaderGlslType.float, '4.0'),
      _p('warp', ShaderGlslType.float, '0.25'),
      _p('detail', ShaderGlslType.float, '0.25'),
      _p('amplitude', ShaderGlslType.float, '1.0'),
      _p('seed', ShaderGlslType.float, '0.0'),
    ],
    [_p('height', ShaderGlslType.float)],
  ),
  _d(
    'sampled_terrain_normal',
    'Sampled Terrain Normal',
    'Terrain',
    [
      _p('uv', ShaderGlslType.vec2, 'vec2(0.0)'),
      _p('scale', ShaderGlslType.float, '4.0'),
      _p('warp', ShaderGlslType.float, '0.25'),
      _p('detail', ShaderGlslType.float, '0.25'),
      _p('amplitude', ShaderGlslType.float, '1.0'),
      _p('seed', ShaderGlslType.float, '0.0'),
      _p('spacing', ShaderGlslType.float, '0.004'),
      _p('strength', ShaderGlslType.float, '1.0'),
    ],
    [
      _p('normal', ShaderGlslType.vec3),
      _p('height', ShaderGlslType.float),
      _p('slope', ShaderGlslType.float),
    ],
  ),

  // Vector
  _d(
    'vec2_compose',
    'Compose Vec2',
    'Vector',
    [
      _p('x', ShaderGlslType.float, '0.0'),
      _p('y', ShaderGlslType.float, '0.0'),
    ],
    [_p('result', ShaderGlslType.vec2, null, 'Vec2')],
  ),
  _d(
    'tile_uv',
    'Tile UV',
    'Vector',
    [
      _p('uv', ShaderGlslType.vec2, 'vec2(0.0)'),
      _p('scale', ShaderGlslType.float, '2.0'),
    ],
    [_p('uv', ShaderGlslType.vec2)],
  ),
  _d(
    'rotate_uv',
    'Rotate UV',
    'Vector',
    [
      _p('uv', ShaderGlslType.vec2, 'vec2(0.0)'),
      _p('angle', ShaderGlslType.float, '0.0'),
    ],
    [_p('uv', ShaderGlslType.vec2)],
  ),
  _d(
    'vec2_split',
    'Split Vec2',
    'Vector',
    [_p('v', ShaderGlslType.vec2, 'vec2(0.0)', 'Vec2')],
    [_p('x', ShaderGlslType.float), _p('y', ShaderGlslType.float)],
  ),
  _d(
    'vec3_compose',
    'Compose Vec3',
    'Vector',
    [
      _p('x', ShaderGlslType.float, '0.0', 'R / X'),
      _p('y', ShaderGlslType.float, '0.0', 'G / Y'),
      _p('z', ShaderGlslType.float, '0.0', 'B / Z'),
    ],
    [_p('result', ShaderGlslType.vec3, null, 'Vec3')],
  ),
  _d(
    'vec3_split',
    'Split Vec3',
    'Vector',
    [_p('v', ShaderGlslType.vec3, 'vec3(0.0)', 'Vec3')],
    [
      _p('x', ShaderGlslType.float, null, 'R / X'),
      _p('y', ShaderGlslType.float, null, 'G / Y'),
      _p('z', ShaderGlslType.float, null, 'B / Z'),
    ],
  ),
  _d(
    'length',
    'Length',
    'Vector',
    [_p('v', ShaderGlslType.vec2, 'vec2(0.0)')],
    [_p('result', ShaderGlslType.float, null, 'Length')],
  ),
  _d(
    'distance',
    'Distance',
    'Vector',
    [
      _p('a', ShaderGlslType.vec2, 'vec2(0.0)'),
      _p('b', ShaderGlslType.vec2, 'vec2(0.0)'),
    ],
    [_p('result', ShaderGlslType.float, null, 'Dist')],
  ),
  _d(
    'dot',
    'Dot Product',
    'Vector',
    [
      _p('a', ShaderGlslType.vec2, 'vec2(0.0)'),
      _p('b', ShaderGlslType.vec2, 'vec2(1.0)'),
    ],
    [_p('result', ShaderGlslType.float, null, 'Dot')],
  ),

  // Color
  _d(
    'mix_color',
    'Mix Colors',
    'Color',
    [
      _p('a', ShaderGlslType.vec3, 'vec3(0.0)', 'Color A'),
      _p('b', ShaderGlslType.vec3, 'vec3(1.0)', 'Color B'),
      _p('t', ShaderGlslType.float, '0.5'),
    ],
    [_p('result', ShaderGlslType.vec3, null, 'Color')],
  ),
  _d(
    'gradient_color',
    'Gradient',
    'Color',
    [
      _p('a', ShaderGlslType.vec3, 'u_accent', 'Color A'),
      _p('b', ShaderGlslType.vec3, 'u_secondary', 'Color B'),
      _p('factor', ShaderGlslType.float, '0.5'),
    ],
    [_p('color', ShaderGlslType.vec3)],
  ),
  _d(
    'color_ramp',
    'Color Ramp',
    'Color',
    [
      _p('factor', ShaderGlslType.float, '0.5'),
      _p('low', ShaderGlslType.vec3, 'vec3(0.08, 0.20, 0.08)'),
      _p('mid', ShaderGlslType.vec3, 'vec3(0.42, 0.34, 0.22)'),
      _p('high', ShaderGlslType.vec3, 'vec3(0.92, 0.92, 0.86)'),
      _p('midpoint', ShaderGlslType.float, '0.55'),
      _p('softness', ShaderGlslType.float, '0.12'),
    ],
    [_p('color', ShaderGlslType.vec3)],
  ),
  _d(
    'biome_mask',
    'Biome Mask',
    'Color',
    [
      _p('height', ShaderGlslType.float, '0.0'),
      _p('slope', ShaderGlslType.float, '0.0'),
      _p('minHeight', ShaderGlslType.float, '0.0'),
      _p('maxHeight', ShaderGlslType.float, '1.0'),
      _p('maxSlope', ShaderGlslType.float, '1.0'),
      _p('softness', ShaderGlslType.float, '0.08'),
    ],
    [_p('mask', ShaderGlslType.float)],
  ),
  _d(
    'altitude_bands',
    'Altitude Bands',
    'Color',
    [
      _p('height', ShaderGlslType.float, '0.0'),
      _p('grassLine', ShaderGlslType.float, '0.25'),
      _p('rockLine', ShaderGlslType.float, '0.58'),
      _p('snowLine', ShaderGlslType.float, '0.78'),
      _p('softness', ShaderGlslType.float, '0.08'),
      _p('grass', ShaderGlslType.vec3, 'vec3(0.10, 0.36, 0.12)'),
      _p('rock', ShaderGlslType.vec3, 'vec3(0.42, 0.38, 0.32)'),
      _p('snow', ShaderGlslType.vec3, 'vec3(0.92, 0.92, 0.86)'),
    ],
    [
      _p('color', ShaderGlslType.vec3),
      _p('grassMask', ShaderGlslType.float),
      _p('rockMask', ShaderGlslType.float),
      _p('snowMask', ShaderGlslType.float),
    ],
  ),
  _d(
    'mask_blend_color',
    'Mask Blend Color',
    'Color',
    [
      _p('base', ShaderGlslType.vec3, 'vec3(0.0)'),
      _p('detail', ShaderGlslType.vec3, 'vec3(1.0)'),
      _p('mask', ShaderGlslType.float, '0.5'),
    ],
    [_p('color', ShaderGlslType.vec3)],
  ),

  // Lighting / material
  _d(
    'sun_direction',
    'Sun Direction',
    'Lighting',
    [
      _p('azimuth', ShaderGlslType.float, '0.65'),
      _p('elevation', ShaderGlslType.float, '0.55'),
    ],
    [_p('direction', ShaderGlslType.vec3)],
  ),
  _d(
    'diffuse_lighting',
    'Diffuse Lighting',
    'Lighting',
    [
      _p('color', ShaderGlslType.vec3, 'vec3(1.0)'),
      _p('normal', ShaderGlslType.vec3, 'vec3(0.0, 0.0, 1.0)'),
      _p('lightDir', ShaderGlslType.vec3, 'vec3(0.25, 0.35, 0.9)'),
      _p('intensity', ShaderGlslType.float, '1.0'),
      _p('ambient', ShaderGlslType.float, '0.2'),
    ],
    [_p('color', ShaderGlslType.vec3), _p('light', ShaderGlslType.float)],
  ),
  _d(
    'specular_lighting',
    'Specular',
    'Lighting',
    [
      _p('normal', ShaderGlslType.vec3, 'vec3(0.0, 0.0, 1.0)'),
      _p('lightDir', ShaderGlslType.vec3, 'vec3(0.25, 0.35, 0.9)'),
      _p('viewDir', ShaderGlslType.vec3, 'vec3(0.0, 0.0, 1.0)'),
      _p('shininess', ShaderGlslType.float, '32.0'),
      _p('intensity', ShaderGlslType.float, '0.35'),
    ],
    [_p('specular', ShaderGlslType.float)],
  ),
  _d(
    'ambient_light',
    'Ambient Light',
    'Lighting',
    [
      _p('color', ShaderGlslType.vec3, 'vec3(1.0)'),
      _p('ambientColor', ShaderGlslType.vec3, 'vec3(0.35, 0.40, 0.50)'),
      _p('intensity', ShaderGlslType.float, '0.2'),
    ],
    [_p('color', ShaderGlslType.vec3)],
  ),
  _d(
    'fog',
    'Fog',
    'Lighting',
    [
      _p('color', ShaderGlslType.vec3, 'vec3(1.0)'),
      _p('fogColor', ShaderGlslType.vec3, 'vec3(0.55, 0.62, 0.70)'),
      _p('depth', ShaderGlslType.float, '0.0'),
      _p('density', ShaderGlslType.float, '0.45'),
    ],
    [_p('color', ShaderGlslType.vec3)],
  ),
  _d(
    'simple_shadow',
    'Simple Shadow',
    'Lighting',
    [
      _p('normal', ShaderGlslType.vec3, 'vec3(0.0, 0.0, 1.0)'),
      _p('lightDir', ShaderGlslType.vec3, 'vec3(0.25, 0.35, 0.9)'),
      _p('softness', ShaderGlslType.float, '0.25'),
    ],
    [_p('shadow', ShaderGlslType.float)],
  ),
  _d(
    'ambient_occlusion',
    'Ambient Occlusion',
    'Lighting',
    [
      _p('curvature', ShaderGlslType.float, '0.0'),
      _p('slope', ShaderGlslType.float, '0.0'),
      _p('strength', ShaderGlslType.float, '0.6'),
    ],
    [_p('ao', ShaderGlslType.float)],
  ),
  _d(
    'normal_strength',
    'Normal Strength',
    'Material',
    [
      _p('normal', ShaderGlslType.vec3, 'vec3(0.0, 0.0, 1.0)'),
      _p('strength', ShaderGlslType.float, '1.0'),
    ],
    [_p('normal', ShaderGlslType.vec3)],
  ),
  _d(
    'triplanar_coords',
    'Triplanar Coordinates',
    'Material',
    [
      _p('position', ShaderGlslType.vec3, 'vec3(0.0)'),
      _p('normal', ShaderGlslType.vec3, 'vec3(0.0, 0.0, 1.0)'),
      _p('scale', ShaderGlslType.float, '1.0'),
      _p('sharpness', ShaderGlslType.float, '4.0'),
    ],
    [
      _p('xUV', ShaderGlslType.vec2),
      _p('yUV', ShaderGlslType.vec2),
      _p('zUV', ShaderGlslType.vec2),
      _p('weights', ShaderGlslType.vec3),
    ],
  ),
  _d(
    'layer_mask',
    'Layer Mask',
    'Material',
    [
      _p('height', ShaderGlslType.float, '0.0'),
      _p('slope', ShaderGlslType.float, '0.0'),
      _p('noise', ShaderGlslType.float, '0.5'),
      _p('heightMin', ShaderGlslType.float, '0.0'),
      _p('heightMax', ShaderGlslType.float, '1.0'),
      _p('slopeMax', ShaderGlslType.float, '1.0'),
      _p('noiseAmount', ShaderGlslType.float, '0.0'),
      _p('softness', ShaderGlslType.float, '0.08'),
    ],
    [_p('mask', ShaderGlslType.float)],
  ),
  _d(
    'fresnel',
    'Fresnel',
    'Material',
    [
      _p('normal', ShaderGlslType.vec3, 'vec3(0.0, 0.0, 1.0)'),
      _p('viewDir', ShaderGlslType.vec3, 'vec3(0.0, 0.0, 1.0)'),
      _p('power', ShaderGlslType.float, '5.0'),
      _p('bias', ShaderGlslType.float, '0.0'),
      _p('scale', ShaderGlslType.float, '1.0'),
    ],
    [_p('factor', ShaderGlslType.float)],
  ),
  _d(
    'rough_specular',
    'Rough Specular',
    'Material',
    [
      _p('normal', ShaderGlslType.vec3, 'vec3(0.0, 0.0, 1.0)'),
      _p('lightDir', ShaderGlslType.vec3, 'vec3(0.25, 0.35, 0.9)'),
      _p('viewDir', ShaderGlslType.vec3, 'vec3(0.0, 0.0, 1.0)'),
      _p('roughness', ShaderGlslType.float, '0.45'),
      _p('intensity', ShaderGlslType.float, '0.35'),
    ],
    [_p('specular', ShaderGlslType.float)],
  ),

  // Camera / raymarch
  _d(
    'camera_ray',
    'Camera Ray',
    'Camera',
    [
      _p('uv', ShaderGlslType.vec2, 'vec2(0.5)'),
      _p('position', ShaderGlslType.vec3, 'vec3(0.0, 0.0, 2.5)'),
      _p('target', ShaderGlslType.vec3, 'vec3(0.0, 0.0, 0.0)'),
      _p('fov', ShaderGlslType.float, '0.8'),
      _p('aspect', ShaderGlslType.float, '1.7777778'),
    ],
    [_p('origin', ShaderGlslType.vec3), _p('direction', ShaderGlslType.vec3)],
  ),
  _d(
    'ray_point',
    'Ray Point',
    'Camera',
    [
      _p('origin', ShaderGlslType.vec3, 'vec3(0.0)'),
      _p('direction', ShaderGlslType.vec3, 'vec3(0.0, 0.0, -1.0)'),
      _p('depth', ShaderGlslType.float, '1.0'),
    ],
    [_p('point', ShaderGlslType.vec3)],
  ),
  _d(
    'sdf_sphere',
    'SDF Sphere',
    'Camera',
    [
      _p('point', ShaderGlslType.vec3, 'vec3(0.0)'),
      _p('center', ShaderGlslType.vec3, 'vec3(0.0)'),
      _p('radius', ShaderGlslType.float, '1.0'),
    ],
    [_p('distance', ShaderGlslType.float)],
  ),
  _d(
    'sdf_plane',
    'SDF Plane',
    'Camera',
    [
      _p('point', ShaderGlslType.vec3, 'vec3(0.0)'),
      _p('height', ShaderGlslType.float, '0.0'),
    ],
    [_p('distance', ShaderGlslType.float)],
  ),
  _d(
    'raymarch_sphere',
    'Raymarch Sphere',
    'Camera',
    [
      _p('origin', ShaderGlslType.vec3, 'vec3(0.0)'),
      _p('direction', ShaderGlslType.vec3, 'vec3(0.0, 0.0, -1.0)'),
      _p('center', ShaderGlslType.vec3, 'vec3(0.0)'),
      _p('radius', ShaderGlslType.float, '1.0'),
      _p('maxDistance', ShaderGlslType.float, '20.0'),
      _p('maxSteps', ShaderGlslType.float, '64.0'),
    ],
    [_p('depth', ShaderGlslType.float), _p('hit', ShaderGlslType.float)],
  ),
  _d(
    'depth_fade',
    'Depth Fade',
    'Camera',
    [
      _p('depth', ShaderGlslType.float, '0.0'),
      _p('near', ShaderGlslType.float, '0.0'),
      _p('far', ShaderGlslType.float, '10.0'),
    ],
    [_p('factor', ShaderGlslType.float)],
  ),

  // Utility / output
  _d(
    'reroute_float',
    'Reroute Float',
    'Utility',
    [_p('value', ShaderGlslType.float, '0.0')],
    [_p('value', ShaderGlslType.float, null, 'Out')],
  ),
  _d(
    'reroute_vec2',
    'Reroute Vec2',
    'Utility',
    [_p('value', ShaderGlslType.vec2, 'vec2(0.0)')],
    [_p('value', ShaderGlslType.vec2, null, 'Out')],
  ),
  _d(
    'reroute_vec3',
    'Reroute Vec3',
    'Utility',
    [_p('value', ShaderGlslType.vec3, 'vec3(0.0)')],
    [_p('value', ShaderGlslType.vec3, null, 'Out')],
  ),
  _d('fragment_output', 'Fragment Output', 'Output', [
    _p('color', ShaderGlslType.vec3, 'vec3(0.0)'),
    _p('alpha', ShaderGlslType.float, '1.0'),
  ], const []),
];

final shaderNodeDefinitionById = <String, ShaderNodeDefinition>{
  for (final definition in shaderNodeDefinitions) definition.id: definition,
};

final shaderNodeCategories = <String>[
  for (final definition in shaderNodeDefinitions)
    if (!shaderNodeDefinitions
        .takeWhile((item) => item != definition)
        .any((item) => item.category == definition.category))
      definition.category,
];
