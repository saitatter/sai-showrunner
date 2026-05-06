/**
 * Shader Node Graph — Types, node definitions, and GLSL code generation.
 *
 * Each node has typed input/output ports. The graph compiler does a topological
 * sort and emits a single GLSL fragment shader.
 */

// ─── Port & Node Types ───────────────────────────────────────────────

export type GlslType = "float" | "vec2" | "vec3" | "vec4"

export interface ShaderPortDef {
	key: string
	label: string
	type: GlslType
	default?: string // GLSL literal default, e.g. "0.0", "vec3(1.0)"
}

export interface ShaderNodeDef {
	id: string
	name: string
	category: string
	icon: string
	inputs: ShaderPortDef[]
	outputs: ShaderPortDef[]
	/** Return GLSL lines that compute output variables from input variables.
	 *  `ins` maps input key → GLSL variable name, `outs` maps output key → GLSL variable name. */
	compile: (ins: Record<string, string>, outs: Record<string, string>) => string[]
}

// ─── Graph Instance Types ────────────────────────────────────────────

export interface ShaderNodeInstance {
	id: string
	defId: string
	x: number
	y: number
	/** Override default values for unconnected inputs */
	inputDefaults?: Record<string, string | number>
}

export interface ShaderWire {
	id: string
	fromNode: string
	fromPort: string
	toNode: string
	toPort: string
}

export interface ShaderGraph {
	nodes: ShaderNodeInstance[]
	wires: ShaderWire[]
	outputNodeId?: string
}

export type ShaderUniformValue = number | [number, number] | [number, number, number] | [number, number, number, number]
export type ShaderUniformValueMap = Record<string, ShaderUniformValue>

// ─── Built-in Node Definitions ───────────────────────────────────────

export const SHADER_NODE_DEFS: ShaderNodeDef[] = [
	// ── Input ──
	{
		id: "uv",
		name: "UV Coordinates",
		category: "Input",
		icon: "mdi mdi-grid",
		inputs: [],
		outputs: [{ key: "uv", label: "UV", type: "vec2" }],
		compile: (_ins, outs) => [
			`${outs.uv} = gl_FragCoord.xy / u_resolution;`,
		],
	},
	{
		id: "time",
		name: "Time",
		category: "Input",
		icon: "mdi mdi-clock-outline",
		inputs: [],
		outputs: [{ key: "t", label: "Time", type: "float" }],
		compile: (_ins, outs) => [`${outs.t} = u_time;`],
	},
	{
		id: "resolution",
		name: "Resolution",
		category: "Input",
		icon: "mdi mdi-monitor-screenshot",
		inputs: [],
		outputs: [{ key: "res", label: "Resolution", type: "vec2" }],
		compile: (_ins, outs) => [`${outs.res} = u_resolution;`],
	},
	{
		id: "accent_color",
		name: "Accent Color",
		category: "Input",
		icon: "mdi mdi-palette",
		inputs: [],
		outputs: [{ key: "color", label: "Color", type: "vec3" }],
		compile: (_ins, outs) => [`${outs.color} = u_accent;`],
	},
	{
		id: "secondary_color",
		name: "Secondary Color",
		category: "Input",
		icon: "mdi mdi-palette-outline",
		inputs: [],
		outputs: [{ key: "color", label: "Color", type: "vec3" }],
		compile: (_ins, outs) => [`${outs.color} = u_secondary;`],
	},
	{
		id: "float_const",
		name: "Float",
		category: "Input",
		icon: "mdi mdi-numeric",
		inputs: [],
		outputs: [{ key: "value", label: "Value", type: "float", default: "1.0" }],
		compile: (_ins, outs) => [`// float constant assigned via default`],
	},
	{
		id: "vec3_const",
		name: "Color / Vec3",
		category: "Input",
		icon: "mdi mdi-palette-swatch",
		inputs: [],
		outputs: [{ key: "value", label: "Value", type: "vec3", default: "vec3(1.0, 1.0, 1.0)" }],
		compile: (_ins, outs) => [`// vec3 constant assigned via default`],
	},
	{
		id: "uniform_float",
		name: "Float Parameter",
		category: "Input",
		icon: "mdi mdi-tune-variant",
		inputs: [],
		outputs: [{ key: "value", label: "Value", type: "float", default: "1.0" }],
		compile: (_ins, outs) => [`// float parameter assigned from uniform`],
	},
	{
		id: "uniform_vec2",
		name: "Vec2 Parameter",
		category: "Input",
		icon: "mdi mdi-vector-point",
		inputs: [],
		outputs: [{ key: "value", label: "Vec2", type: "vec2", default: "vec2(0.0, 0.0)" }],
		compile: (_ins, outs) => [`// vec2 parameter assigned from uniform`],
	},
	{
		id: "uniform_vec3",
		name: "Color Parameter",
		category: "Input",
		icon: "mdi mdi-palette-advanced",
		inputs: [],
		outputs: [{ key: "value", label: "Color", type: "vec3", default: "vec3(1.0, 1.0, 1.0)" }],
		compile: (_ins, outs) => [`// color parameter assigned from uniform`],
	},
	{
		id: "camera_position",
		name: "Camera Position",
		category: "Input",
		icon: "mdi mdi-camera-marker",
		inputs: [],
		outputs: [{ key: "position", label: "Position", type: "vec3", default: "vec3(0.0, 0.0, 2.5)" }],
		compile: (_ins, outs) => [`${outs.position} = u_camera_position;`],
	},
	{
		id: "camera_target",
		name: "Camera Target",
		category: "Input",
		icon: "mdi mdi-crosshairs-gps",
		inputs: [],
		outputs: [{ key: "target", label: "Target", type: "vec3", default: "vec3(0.0, 0.0, 0.0)" }],
		compile: (_ins, outs) => [`${outs.target} = u_camera_target;`],
	},
	{
		id: "mouse_position",
		name: "Mouse Position",
		category: "Input",
		icon: "mdi mdi-cursor-default-click",
		inputs: [],
		outputs: [{ key: "mouse", label: "Mouse", type: "vec2", default: "vec2(0.0)" }],
		compile: (_ins, outs) => [`${outs.mouse} = u_mouse;`],
	},

	// ── Math ──
	{
		id: "add",
		name: "Add",
		category: "Math",
		icon: "mdi mdi-plus",
		inputs: [
			{ key: "a", label: "A", type: "float", default: "0.0" },
			{ key: "b", label: "B", type: "float", default: "0.0" },
		],
		outputs: [{ key: "result", label: "Result", type: "float" }],
		compile: (ins, outs) => [`${outs.result} = ${ins.a} + ${ins.b};`],
	},
	{
		id: "subtract",
		name: "Subtract",
		category: "Math",
		icon: "mdi mdi-minus",
		inputs: [
			{ key: "a", label: "A", type: "float", default: "0.0" },
			{ key: "b", label: "B", type: "float", default: "0.0" },
		],
		outputs: [{ key: "result", label: "Result", type: "float" }],
		compile: (ins, outs) => [`${outs.result} = ${ins.a} - ${ins.b};`],
	},
	{
		id: "multiply",
		name: "Multiply",
		category: "Math",
		icon: "mdi mdi-close",
		inputs: [
			{ key: "a", label: "A", type: "float", default: "1.0" },
			{ key: "b", label: "B", type: "float", default: "1.0" },
		],
		outputs: [{ key: "result", label: "Result", type: "float" }],
		compile: (ins, outs) => [`${outs.result} = ${ins.a} * ${ins.b};`],
	},
	{
		id: "divide",
		name: "Divide",
		category: "Math",
		icon: "mdi mdi-division",
		inputs: [
			{ key: "a", label: "A", type: "float", default: "1.0" },
			{ key: "b", label: "B", type: "float", default: "1.0" },
		],
		outputs: [{ key: "result", label: "Result", type: "float" }],
		compile: (ins, outs) => [`${outs.result} = ${ins.a} / max(${ins.b}, 0.0001);`],
	},
	{
		id: "sin",
		name: "Sin",
		category: "Math",
		icon: "mdi mdi-sine-wave",
		inputs: [{ key: "x", label: "X", type: "float", default: "0.0" }],
		outputs: [{ key: "result", label: "Result", type: "float" }],
		compile: (ins, outs) => [`${outs.result} = sin(${ins.x});`],
	},
	{
		id: "cos",
		name: "Cos",
		category: "Math",
		icon: "mdi mdi-cosine-wave",
		inputs: [{ key: "x", label: "X", type: "float", default: "0.0" }],
		outputs: [{ key: "result", label: "Result", type: "float" }],
		compile: (ins, outs) => [`${outs.result} = cos(${ins.x});`],
	},
	{
		id: "abs",
		name: "Abs",
		category: "Math",
		icon: "mdi mdi-absolute-value",
		inputs: [{ key: "x", label: "X", type: "float", default: "0.0" }],
		outputs: [{ key: "result", label: "Result", type: "float" }],
		compile: (ins, outs) => [`${outs.result} = abs(${ins.x});`],
	},
	{
		id: "fract",
		name: "Fract",
		category: "Math",
		icon: "mdi mdi-fraction-one-half",
		inputs: [{ key: "x", label: "X", type: "float", default: "0.0" }],
		outputs: [{ key: "result", label: "Result", type: "float" }],
		compile: (ins, outs) => [`${outs.result} = fract(${ins.x});`],
	},
	{
		id: "smoothstep",
		name: "Smoothstep",
		category: "Math",
		icon: "mdi mdi-chart-bell-curve-cumulative",
		inputs: [
			{ key: "edge0", label: "Edge 0", type: "float", default: "0.0" },
			{ key: "edge1", label: "Edge 1", type: "float", default: "1.0" },
			{ key: "x", label: "X", type: "float", default: "0.5" },
		],
		outputs: [{ key: "result", label: "Result", type: "float" }],
		compile: (ins, outs) => [`${outs.result} = smoothstep(${ins.edge0}, ${ins.edge1}, ${ins.x});`],
	},
	{
		id: "clamp",
		name: "Clamp",
		category: "Math",
		icon: "mdi mdi-arrow-collapse-horizontal",
		inputs: [
			{ key: "x", label: "X", type: "float", default: "0.0" },
			{ key: "lo", label: "Min", type: "float", default: "0.0" },
			{ key: "hi", label: "Max", type: "float", default: "1.0" },
		],
		outputs: [{ key: "result", label: "Result", type: "float" }],
		compile: (ins, outs) => [`${outs.result} = clamp(${ins.x}, ${ins.lo}, ${ins.hi});`],
	},
	{
		id: "mix_float",
		name: "Mix (Lerp)",
		category: "Math",
		icon: "mdi mdi-blend",
		inputs: [
			{ key: "a", label: "A", type: "float", default: "0.0" },
			{ key: "b", label: "B", type: "float", default: "1.0" },
			{ key: "t", label: "T", type: "float", default: "0.5" },
		],
		outputs: [{ key: "result", label: "Result", type: "float" }],
		compile: (ins, outs) => [`${outs.result} = mix(${ins.a}, ${ins.b}, ${ins.t});`],
	},
	{
		id: "wave",
		name: "Wave",
		category: "Math",
		icon: "mdi mdi-sine-wave",
		inputs: [
			{ key: "x", label: "X", type: "float", default: "0.0" },
			{ key: "time", label: "Time", type: "float", default: "0.0" },
			{ key: "frequency", label: "Frequency", type: "float", default: "6.0" },
			{ key: "speed", label: "Speed", type: "float", default: "1.0" },
		],
		outputs: [{ key: "result", label: "Wave", type: "float" }],
		compile: (ins, outs) => [`${outs.result} = 0.5 + 0.5 * sin(${ins.x} * ${ins.frequency} + ${ins.time} * ${ins.speed});`],
	},

	// ── Noise ──
	{
		id: "value_noise",
		name: "Value Noise",
		category: "Noise",
		icon: "mdi mdi-blur",
		inputs: [
			{ key: "uv", label: "UV", type: "vec2", default: "vec2(0.0)" },
			{ key: "scale", label: "Scale", type: "float", default: "6.0" },
			{ key: "seed", label: "Seed", type: "float", default: "0.0" },
		],
		outputs: [{ key: "value", label: "Value", type: "float" }],
		compile: (ins, outs) => [`${outs.value} = sr_value_noise(${ins.uv} * ${ins.scale} + vec2(${ins.seed}));`],
	},
	{
		id: "perlin_noise",
		name: "Perlin Noise",
		category: "Noise",
		icon: "mdi mdi-chart-bell-curve",
		inputs: [
			{ key: "uv", label: "UV", type: "vec2", default: "vec2(0.0)" },
			{ key: "scale", label: "Scale", type: "float", default: "6.0" },
			{ key: "seed", label: "Seed", type: "float", default: "0.0" },
		],
		outputs: [{ key: "value", label: "Value", type: "float" }],
		compile: (ins, outs) => [`${outs.value} = clamp(0.5 + 0.5 * sr_perlin_noise(${ins.uv} * ${ins.scale} + vec2(${ins.seed})), 0.0, 1.0);`],
	},
	{
		id: "fbm_noise",
		name: "FBM Noise",
		category: "Noise",
		icon: "mdi mdi-waves",
		inputs: [
			{ key: "uv", label: "UV", type: "vec2", default: "vec2(0.0)" },
			{ key: "scale", label: "Scale", type: "float", default: "4.0" },
			{ key: "octaves", label: "Octaves", type: "float", default: "5.0" },
			{ key: "lacunarity", label: "Lacunarity", type: "float", default: "2.0" },
			{ key: "gain", label: "Gain", type: "float", default: "0.5" },
			{ key: "seed", label: "Seed", type: "float", default: "0.0" },
		],
		outputs: [{ key: "value", label: "Value", type: "float" }],
		compile: (ins, outs) => [`${outs.value} = sr_fbm(${ins.uv} * ${ins.scale} + vec2(${ins.seed}), ${ins.octaves}, ${ins.lacunarity}, ${ins.gain});`],
	},
	{
		id: "voronoi_noise",
		name: "Voronoi",
		category: "Noise",
		icon: "mdi mdi-hexagon-multiple-outline",
		inputs: [
			{ key: "uv", label: "UV", type: "vec2", default: "vec2(0.0)" },
			{ key: "scale", label: "Scale", type: "float", default: "8.0" },
			{ key: "jitter", label: "Jitter", type: "float", default: "0.8" },
			{ key: "seed", label: "Seed", type: "float", default: "0.0" },
		],
		outputs: [{ key: "distance", label: "Distance", type: "float" }],
		compile: (ins, outs) => [`${outs.distance} = sr_voronoi(${ins.uv} * ${ins.scale} + vec2(${ins.seed}), ${ins.jitter});`],
	},
	{
		id: "domain_warp",
		name: "Domain Warp",
		category: "Noise",
		icon: "mdi mdi-vector-polyline",
		inputs: [
			{ key: "uv", label: "UV", type: "vec2", default: "vec2(0.0)" },
			{ key: "scale", label: "Scale", type: "float", default: "3.0" },
			{ key: "strength", label: "Strength", type: "float", default: "0.25" },
			{ key: "seed", label: "Seed", type: "float", default: "0.0" },
		],
		outputs: [
			{ key: "uv", label: "Warped UV", type: "vec2" },
			{ key: "value", label: "Value", type: "float" },
		],
		compile: (ins, outs) => [
			`${outs.uv} = sr_domain_warp(${ins.uv} * ${ins.scale} + vec2(${ins.seed}), ${ins.strength});`,
			`${outs.value} = sr_fbm(${outs.uv}, 5.0, 2.0, 0.5);`,
		],
	},

	// ── Terrain ──
	{
		id: "terrain_height",
		name: "Terrain Height",
		category: "Terrain",
		icon: "mdi mdi-image-filter-hdr",
		inputs: [
			{ key: "base", label: "Base", type: "float", default: "0.0" },
			{ key: "detail", label: "Detail", type: "float", default: "0.0" },
			{ key: "amplitude", label: "Amplitude", type: "float", default: "1.0" },
			{ key: "detailStrength", label: "Detail Strength", type: "float", default: "0.25" },
			{ key: "offset", label: "Offset", type: "float", default: "0.0" },
		],
		outputs: [{ key: "height", label: "Height", type: "float" }],
		compile: (ins, outs) => [`${outs.height} = (${ins.base} + ${ins.detail} * ${ins.detailStrength}) * ${ins.amplitude} + ${ins.offset};`],
	},
	{
		id: "height_remap",
		name: "Remap Height",
		category: "Terrain",
		icon: "mdi mdi-tune-vertical",
		inputs: [
			{ key: "height", label: "Height", type: "float", default: "0.0" },
			{ key: "min", label: "Min", type: "float", default: "0.0" },
			{ key: "max", label: "Max", type: "float", default: "1.0" },
			{ key: "power", label: "Power", type: "float", default: "1.0" },
		],
		outputs: [{ key: "height", label: "Height", type: "float" }],
		compile: (ins, outs) => [`${outs.height} = pow(clamp((${ins.height} - ${ins.min}) / max(${ins.max} - ${ins.min}, 0.0001), 0.0, 1.0), max(${ins.power}, 0.0001));`],
	},
	{
		id: "normal_from_height",
		name: "Normal From Height",
		category: "Terrain",
		icon: "mdi mdi-axis-arrow",
		inputs: [
			{ key: "center", label: "Center", type: "float", default: "0.0" },
			{ key: "right", label: "Right", type: "float", default: "0.0" },
			{ key: "up", label: "Up", type: "float", default: "0.0" },
			{ key: "spacing", label: "Spacing", type: "float", default: "0.01" },
			{ key: "strength", label: "Strength", type: "float", default: "1.0" },
		],
		outputs: [{ key: "normal", label: "Normal", type: "vec3" }],
		compile: (ins, outs) => [
			`${outs.normal} = normalize(vec3((${ins.center} - ${ins.right}) * ${ins.strength}, (${ins.center} - ${ins.up}) * ${ins.strength}, max(${ins.spacing}, 0.0001)));`,
		],
	},
	{
		id: "slope_mask",
		name: "Slope Mask",
		category: "Terrain",
		icon: "mdi mdi-angle-acute",
		inputs: [
			{ key: "normal", label: "Normal", type: "vec3", default: "vec3(0.0, 0.0, 1.0)" },
			{ key: "minSlope", label: "Min Slope", type: "float", default: "0.2" },
			{ key: "maxSlope", label: "Max Slope", type: "float", default: "0.8" },
		],
		outputs: [{ key: "mask", label: "Mask", type: "float" }],
		compile: (ins, outs) => [`${outs.mask} = smoothstep(${ins.minSlope}, ${ins.maxSlope}, 1.0 - clamp(${ins.normal}.z, 0.0, 1.0));`],
	},
	{
		id: "curvature_mask",
		name: "Curvature Mask",
		category: "Terrain",
		icon: "mdi mdi-chart-bell-curve",
		inputs: [
			{ key: "center", label: "Center", type: "float", default: "0.0" },
			{ key: "left", label: "Left", type: "float", default: "0.0" },
			{ key: "right", label: "Right", type: "float", default: "0.0" },
			{ key: "down", label: "Down", type: "float", default: "0.0" },
			{ key: "up", label: "Up", type: "float", default: "0.0" },
			{ key: "strength", label: "Strength", type: "float", default: "2.0" },
		],
		outputs: [{ key: "mask", label: "Mask", type: "float" }],
		compile: (ins, outs) => [`${outs.mask} = clamp(abs((${ins.left} + ${ins.right} + ${ins.down} + ${ins.up}) - 4.0 * ${ins.center}) * ${ins.strength}, 0.0, 1.0);`],
	},
	{
		id: "thermal_erosion",
		name: "Thermal Erosion",
		category: "Terrain",
		icon: "mdi mdi-landslide",
		inputs: [
			{ key: "height", label: "Height", type: "float", default: "0.0" },
			{ key: "slope", label: "Slope", type: "float", default: "0.0" },
			{ key: "threshold", label: "Threshold", type: "float", default: "0.35" },
			{ key: "amount", label: "Amount", type: "float", default: "0.08" },
		],
		outputs: [{ key: "height", label: "Height", type: "float" }],
		compile: (ins, outs) => [`${outs.height} = ${ins.height} - max(${ins.slope} - ${ins.threshold}, 0.0) * ${ins.amount};`],
	},

	// ── Vector ──
	{
		id: "vec2_compose",
		name: "Compose Vec2",
		category: "Vector",
		icon: "mdi mdi-vector-point",
		inputs: [
			{ key: "x", label: "X", type: "float", default: "0.0" },
			{ key: "y", label: "Y", type: "float", default: "0.0" },
		],
		outputs: [{ key: "result", label: "Vec2", type: "vec2" }],
		compile: (ins, outs) => [`${outs.result} = vec2(${ins.x}, ${ins.y});`],
	},
	{
		id: "tile_uv",
		name: "Tile UV",
		category: "Vector",
		icon: "mdi mdi-grid-large",
		inputs: [
			{ key: "uv", label: "UV", type: "vec2", default: "vec2(0.0)" },
			{ key: "scale", label: "Scale", type: "float", default: "2.0" },
		],
		outputs: [{ key: "uv", label: "UV", type: "vec2" }],
		compile: (ins, outs) => [`${outs.uv} = fract(${ins.uv} * ${ins.scale});`],
	},
	{
		id: "rotate_uv",
		name: "Rotate UV",
		category: "Vector",
		icon: "mdi mdi-rotate-right",
		inputs: [
			{ key: "uv", label: "UV", type: "vec2", default: "vec2(0.0)" },
			{ key: "angle", label: "Angle", type: "float", default: "0.0" },
		],
		outputs: [{ key: "uv", label: "UV", type: "vec2" }],
		compile: (ins, outs) => [
			`vec2 ${outs.uv}_centered = ${ins.uv} - 0.5;`,
			`float ${outs.uv}_s = sin(${ins.angle});`,
			`float ${outs.uv}_c = cos(${ins.angle});`,
			`${outs.uv} = mat2(${outs.uv}_c, -${outs.uv}_s, ${outs.uv}_s, ${outs.uv}_c) * ${outs.uv}_centered + 0.5;`,
		],
	},
	{
		id: "vec2_split",
		name: "Split Vec2",
		category: "Vector",
		icon: "mdi mdi-arrow-split-horizontal",
		inputs: [{ key: "v", label: "Vec2", type: "vec2", default: "vec2(0.0)" }],
		outputs: [
			{ key: "x", label: "X", type: "float" },
			{ key: "y", label: "Y", type: "float" },
		],
		compile: (ins, outs) => [
			`${outs.x} = ${ins.v}.x;`,
			`${outs.y} = ${ins.v}.y;`,
		],
	},
	{
		id: "vec3_compose",
		name: "Compose Vec3",
		category: "Vector",
		icon: "mdi mdi-cube-outline",
		inputs: [
			{ key: "x", label: "R / X", type: "float", default: "0.0" },
			{ key: "y", label: "G / Y", type: "float", default: "0.0" },
			{ key: "z", label: "B / Z", type: "float", default: "0.0" },
		],
		outputs: [{ key: "result", label: "Vec3", type: "vec3" }],
		compile: (ins, outs) => [`${outs.result} = vec3(${ins.x}, ${ins.y}, ${ins.z});`],
	},
	{
		id: "vec3_split",
		name: "Split Vec3",
		category: "Vector",
		icon: "mdi mdi-arrow-split-vertical",
		inputs: [{ key: "v", label: "Vec3", type: "vec3", default: "vec3(0.0)" }],
		outputs: [
			{ key: "x", label: "R / X", type: "float" },
			{ key: "y", label: "G / Y", type: "float" },
			{ key: "z", label: "B / Z", type: "float" },
		],
		compile: (ins, outs) => [
			`${outs.x} = ${ins.v}.x;`,
			`${outs.y} = ${ins.v}.y;`,
			`${outs.z} = ${ins.v}.z;`,
		],
	},
	{
		id: "length",
		name: "Length",
		category: "Vector",
		icon: "mdi mdi-ruler",
		inputs: [{ key: "v", label: "Vec2", type: "vec2", default: "vec2(0.0)" }],
		outputs: [{ key: "result", label: "Length", type: "float" }],
		compile: (ins, outs) => [`${outs.result} = length(${ins.v});`],
	},
	{
		id: "distance",
		name: "Distance",
		category: "Vector",
		icon: "mdi mdi-map-marker-distance",
		inputs: [
			{ key: "a", label: "A", type: "vec2", default: "vec2(0.0)" },
			{ key: "b", label: "B", type: "vec2", default: "vec2(0.0)" },
		],
		outputs: [{ key: "result", label: "Dist", type: "float" }],
		compile: (ins, outs) => [`${outs.result} = distance(${ins.a}, ${ins.b});`],
	},
	{
		id: "dot",
		name: "Dot Product",
		category: "Vector",
		icon: "mdi mdi-circle-small",
		inputs: [
			{ key: "a", label: "A", type: "vec2", default: "vec2(0.0)" },
			{ key: "b", label: "B", type: "vec2", default: "vec2(1.0)" },
		],
		outputs: [{ key: "result", label: "Dot", type: "float" }],
		compile: (ins, outs) => [`${outs.result} = dot(${ins.a}, ${ins.b});`],
	},

	// ── Color ──
	{
		id: "mix_color",
		name: "Mix Colors",
		category: "Color",
		icon: "mdi mdi-invert-colors",
		inputs: [
			{ key: "a", label: "Color A", type: "vec3", default: "vec3(0.0)" },
			{ key: "b", label: "Color B", type: "vec3", default: "vec3(1.0)" },
			{ key: "t", label: "Factor", type: "float", default: "0.5" },
		],
		outputs: [{ key: "result", label: "Color", type: "vec3" }],
		compile: (ins, outs) => [`${outs.result} = mix(${ins.a}, ${ins.b}, ${ins.t});`],
	},
	{
		id: "gradient_color",
		name: "Gradient",
		category: "Color",
		icon: "mdi mdi-gradient-horizontal",
		inputs: [
			{ key: "a", label: "Color A", type: "vec3", default: "u_accent" },
			{ key: "b", label: "Color B", type: "vec3", default: "u_secondary" },
			{ key: "factor", label: "Factor", type: "float", default: "0.5" },
		],
		outputs: [{ key: "color", label: "Color", type: "vec3" }],
		compile: (ins, outs) => [`${outs.color} = mix(${ins.a}, ${ins.b}, clamp(${ins.factor}, 0.0, 1.0));`],
	},
	{
		id: "color_ramp",
		name: "Color Ramp",
		category: "Color",
		icon: "mdi mdi-gradient-horizontal",
		inputs: [
			{ key: "factor", label: "Factor", type: "float", default: "0.5" },
			{ key: "low", label: "Low", type: "vec3", default: "vec3(0.08, 0.20, 0.08)" },
			{ key: "mid", label: "Mid", type: "vec3", default: "vec3(0.42, 0.34, 0.22)" },
			{ key: "high", label: "High", type: "vec3", default: "vec3(0.92, 0.92, 0.86)" },
			{ key: "midpoint", label: "Midpoint", type: "float", default: "0.55" },
			{ key: "softness", label: "Softness", type: "float", default: "0.12" },
		],
		outputs: [{ key: "color", label: "Color", type: "vec3" }],
		compile: (ins, outs) => [
			`float ${outs.color}_f = clamp(${ins.factor}, 0.0, 1.0);`,
			`float ${outs.color}_m = smoothstep(${ins.midpoint} - ${ins.softness}, ${ins.midpoint} + ${ins.softness}, ${outs.color}_f);`,
			`${outs.color} = mix(mix(${ins.low}, ${ins.mid}, smoothstep(0.0, max(${ins.midpoint}, 0.0001), ${outs.color}_f)), ${ins.high}, ${outs.color}_m);`,
		],
	},
	{
		id: "biome_mask",
		name: "Biome Mask",
		category: "Color",
		icon: "mdi mdi-map",
		inputs: [
			{ key: "height", label: "Height", type: "float", default: "0.0" },
			{ key: "slope", label: "Slope", type: "float", default: "0.0" },
			{ key: "minHeight", label: "Min Height", type: "float", default: "0.0" },
			{ key: "maxHeight", label: "Max Height", type: "float", default: "1.0" },
			{ key: "maxSlope", label: "Max Slope", type: "float", default: "1.0" },
			{ key: "softness", label: "Softness", type: "float", default: "0.08" },
		],
		outputs: [{ key: "mask", label: "Mask", type: "float" }],
		compile: (ins, outs) => [
			`float ${outs.mask}_low = smoothstep(${ins.minHeight} - ${ins.softness}, ${ins.minHeight} + ${ins.softness}, ${ins.height});`,
			`float ${outs.mask}_high = 1.0 - smoothstep(${ins.maxHeight} - ${ins.softness}, ${ins.maxHeight} + ${ins.softness}, ${ins.height});`,
			`float ${outs.mask}_slope = 1.0 - smoothstep(${ins.maxSlope} - ${ins.softness}, ${ins.maxSlope} + ${ins.softness}, ${ins.slope});`,
			`${outs.mask} = clamp(${outs.mask}_low * ${outs.mask}_high * ${outs.mask}_slope, 0.0, 1.0);`,
		],
	},
	{
		id: "altitude_bands",
		name: "Altitude Bands",
		category: "Color",
		icon: "mdi mdi-terrain",
		inputs: [
			{ key: "height", label: "Height", type: "float", default: "0.0" },
			{ key: "grassLine", label: "Grass Line", type: "float", default: "0.25" },
			{ key: "rockLine", label: "Rock Line", type: "float", default: "0.58" },
			{ key: "snowLine", label: "Snow Line", type: "float", default: "0.78" },
			{ key: "softness", label: "Softness", type: "float", default: "0.08" },
			{ key: "grass", label: "Grass", type: "vec3", default: "vec3(0.10, 0.36, 0.12)" },
			{ key: "rock", label: "Rock", type: "vec3", default: "vec3(0.42, 0.38, 0.32)" },
			{ key: "snow", label: "Snow", type: "vec3", default: "vec3(0.92, 0.92, 0.86)" },
		],
		outputs: [
			{ key: "color", label: "Color", type: "vec3" },
			{ key: "grassMask", label: "Grass", type: "float" },
			{ key: "rockMask", label: "Rock", type: "float" },
			{ key: "snowMask", label: "Snow", type: "float" },
		],
		compile: (ins, outs) => [
			`${outs.grassMask} = 1.0 - smoothstep(${ins.rockLine} - ${ins.softness}, ${ins.rockLine} + ${ins.softness}, ${ins.height});`,
			`${outs.rockMask} = smoothstep(${ins.grassLine} - ${ins.softness}, ${ins.grassLine} + ${ins.softness}, ${ins.height}) * (1.0 - smoothstep(${ins.snowLine} - ${ins.softness}, ${ins.snowLine} + ${ins.softness}, ${ins.height}));`,
			`${outs.snowMask} = smoothstep(${ins.snowLine} - ${ins.softness}, ${ins.snowLine} + ${ins.softness}, ${ins.height});`,
			`${outs.color} = mix(mix(${ins.grass}, ${ins.rock}, clamp(${outs.rockMask}, 0.0, 1.0)), ${ins.snow}, clamp(${outs.snowMask}, 0.0, 1.0));`,
		],
	},
	{
		id: "mask_blend_color",
		name: "Mask Blend Color",
		category: "Color",
		icon: "mdi mdi-blur-linear",
		inputs: [
			{ key: "base", label: "Base", type: "vec3", default: "vec3(0.0)" },
			{ key: "detail", label: "Detail", type: "vec3", default: "vec3(1.0)" },
			{ key: "mask", label: "Mask", type: "float", default: "0.5" },
		],
		outputs: [{ key: "color", label: "Color", type: "vec3" }],
		compile: (ins, outs) => [`${outs.color} = mix(${ins.base}, ${ins.detail}, clamp(${ins.mask}, 0.0, 1.0));`],
	},

	// ── Lighting ──
	{
		id: "sun_direction",
		name: "Sun Direction",
		category: "Lighting",
		icon: "mdi mdi-white-balance-sunny",
		inputs: [
			{ key: "azimuth", label: "Azimuth", type: "float", default: "0.65" },
			{ key: "elevation", label: "Elevation", type: "float", default: "0.55" },
		],
		outputs: [{ key: "direction", label: "Direction", type: "vec3" }],
		compile: (ins, outs) => [
			`float ${outs.direction}_az = ${ins.azimuth} * 6.2831853;`,
			`float ${outs.direction}_el = clamp(${ins.elevation}, 0.0, 1.0) * 1.5707963;`,
			`${outs.direction} = normalize(vec3(cos(${outs.direction}_az) * cos(${outs.direction}_el), sin(${outs.direction}_az) * cos(${outs.direction}_el), sin(${outs.direction}_el)));`,
		],
	},
	{
		id: "diffuse_lighting",
		name: "Diffuse Lighting",
		category: "Lighting",
		icon: "mdi mdi-brightness-5",
		inputs: [
			{ key: "color", label: "Color", type: "vec3", default: "vec3(1.0)" },
			{ key: "normal", label: "Normal", type: "vec3", default: "vec3(0.0, 0.0, 1.0)" },
			{ key: "lightDir", label: "Light Dir", type: "vec3", default: "vec3(0.25, 0.35, 0.9)" },
			{ key: "intensity", label: "Intensity", type: "float", default: "1.0" },
			{ key: "ambient", label: "Ambient", type: "float", default: "0.2" },
		],
		outputs: [
			{ key: "color", label: "Color", type: "vec3" },
			{ key: "light", label: "Light", type: "float" },
		],
		compile: (ins, outs) => [
			`${outs.light} = max(dot(normalize(${ins.normal}), normalize(${ins.lightDir})), 0.0) * ${ins.intensity};`,
			`${outs.color} = ${ins.color} * (${ins.ambient} + ${outs.light});`,
		],
	},
	{
		id: "specular_lighting",
		name: "Specular",
		category: "Lighting",
		icon: "mdi mdi-star-four-points",
		inputs: [
			{ key: "normal", label: "Normal", type: "vec3", default: "vec3(0.0, 0.0, 1.0)" },
			{ key: "lightDir", label: "Light Dir", type: "vec3", default: "vec3(0.25, 0.35, 0.9)" },
			{ key: "viewDir", label: "View Dir", type: "vec3", default: "vec3(0.0, 0.0, 1.0)" },
			{ key: "shininess", label: "Shininess", type: "float", default: "32.0" },
			{ key: "intensity", label: "Intensity", type: "float", default: "0.35" },
		],
		outputs: [{ key: "specular", label: "Specular", type: "float" }],
		compile: (ins, outs) => [
			`vec3 ${outs.specular}_halfDir = normalize(normalize(${ins.lightDir}) + normalize(${ins.viewDir}));`,
			`${outs.specular} = pow(max(dot(normalize(${ins.normal}), ${outs.specular}_halfDir), 0.0), max(${ins.shininess}, 1.0)) * ${ins.intensity};`,
		],
	},
	{
		id: "ambient_light",
		name: "Ambient Light",
		category: "Lighting",
		icon: "mdi mdi-weather-night",
		inputs: [
			{ key: "color", label: "Color", type: "vec3", default: "vec3(1.0)" },
			{ key: "ambientColor", label: "Ambient", type: "vec3", default: "vec3(0.35, 0.40, 0.50)" },
			{ key: "intensity", label: "Intensity", type: "float", default: "0.2" },
		],
		outputs: [{ key: "color", label: "Color", type: "vec3" }],
		compile: (ins, outs) => [`${outs.color} = ${ins.color} + ${ins.ambientColor} * ${ins.intensity};`],
	},
	{
		id: "fog",
		name: "Fog",
		category: "Lighting",
		icon: "mdi mdi-weather-fog",
		inputs: [
			{ key: "color", label: "Color", type: "vec3", default: "vec3(1.0)" },
			{ key: "fogColor", label: "Fog Color", type: "vec3", default: "vec3(0.55, 0.62, 0.70)" },
			{ key: "depth", label: "Depth", type: "float", default: "0.0" },
			{ key: "density", label: "Density", type: "float", default: "0.45" },
		],
		outputs: [{ key: "color", label: "Color", type: "vec3" }],
		compile: (ins, outs) => [`${outs.color} = mix(${ins.color}, ${ins.fogColor}, clamp(1.0 - exp(-max(${ins.depth}, 0.0) * ${ins.density}), 0.0, 1.0));`],
	},
	{
		id: "simple_shadow",
		name: "Simple Shadow",
		category: "Lighting",
		icon: "mdi mdi-weather-sunset-down",
		inputs: [
			{ key: "normal", label: "Normal", type: "vec3", default: "vec3(0.0, 0.0, 1.0)" },
			{ key: "lightDir", label: "Light Dir", type: "vec3", default: "vec3(0.25, 0.35, 0.9)" },
			{ key: "softness", label: "Softness", type: "float", default: "0.25" },
		],
		outputs: [{ key: "shadow", label: "Shadow", type: "float" }],
		compile: (ins, outs) => [`${outs.shadow} = smoothstep(-${ins.softness}, ${ins.softness}, dot(normalize(${ins.normal}), normalize(${ins.lightDir})));`],
	},
	{
		id: "ambient_occlusion",
		name: "Ambient Occlusion",
		category: "Lighting",
		icon: "mdi mdi-circle-opacity",
		inputs: [
			{ key: "curvature", label: "Curvature", type: "float", default: "0.0" },
			{ key: "slope", label: "Slope", type: "float", default: "0.0" },
			{ key: "strength", label: "Strength", type: "float", default: "0.6" },
		],
		outputs: [{ key: "ao", label: "AO", type: "float" }],
		compile: (ins, outs) => [`${outs.ao} = clamp(1.0 - (${ins.curvature} * 0.65 + ${ins.slope} * 0.35) * ${ins.strength}, 0.0, 1.0);`],
	},

	// ── Camera / Raymarch ──
	{
		id: "camera_ray",
		name: "Camera Ray",
		category: "Camera",
		icon: "mdi mdi-ray-start-arrow",
		inputs: [
			{ key: "uv", label: "UV", type: "vec2", default: "vec2(0.5)" },
			{ key: "position", label: "Position", type: "vec3", default: "vec3(0.0, 0.0, 2.5)" },
			{ key: "target", label: "Target", type: "vec3", default: "vec3(0.0, 0.0, 0.0)" },
			{ key: "fov", label: "FOV", type: "float", default: "0.8" },
			{ key: "aspect", label: "Aspect", type: "float", default: "1.7777778" },
		],
		outputs: [
			{ key: "origin", label: "Origin", type: "vec3" },
			{ key: "direction", label: "Direction", type: "vec3" },
		],
		compile: (ins, outs) => [
			`${outs.origin} = ${ins.position};`,
			`vec3 ${outs.direction}_forward = normalize(${ins.target} - ${ins.position});`,
			`vec3 ${outs.direction}_right = normalize(cross(${outs.direction}_forward, vec3(0.0, 1.0, 0.0)));`,
			`vec3 ${outs.direction}_up = normalize(cross(${outs.direction}_right, ${outs.direction}_forward));`,
			`vec2 ${outs.direction}_screen = (${ins.uv} * 2.0 - 1.0) * vec2(${ins.aspect}, 1.0) * tan(${ins.fov} * 0.5);`,
			`${outs.direction} = normalize(${outs.direction}_forward + ${outs.direction}_right * ${outs.direction}_screen.x + ${outs.direction}_up * ${outs.direction}_screen.y);`,
		],
	},
	{
		id: "ray_point",
		name: "Ray Point",
		category: "Camera",
		icon: "mdi mdi-ray-vertex",
		inputs: [
			{ key: "origin", label: "Origin", type: "vec3", default: "vec3(0.0)" },
			{ key: "direction", label: "Direction", type: "vec3", default: "vec3(0.0, 0.0, -1.0)" },
			{ key: "depth", label: "Depth", type: "float", default: "1.0" },
		],
		outputs: [{ key: "point", label: "Point", type: "vec3" }],
		compile: (ins, outs) => [`${outs.point} = ${ins.origin} + normalize(${ins.direction}) * ${ins.depth};`],
	},
	{
		id: "sdf_sphere",
		name: "SDF Sphere",
		category: "Camera",
		icon: "mdi mdi-sphere",
		inputs: [
			{ key: "point", label: "Point", type: "vec3", default: "vec3(0.0)" },
			{ key: "center", label: "Center", type: "vec3", default: "vec3(0.0)" },
			{ key: "radius", label: "Radius", type: "float", default: "1.0" },
		],
		outputs: [{ key: "distance", label: "Distance", type: "float" }],
		compile: (ins, outs) => [`${outs.distance} = length(${ins.point} - ${ins.center}) - ${ins.radius};`],
	},
	{
		id: "sdf_plane",
		name: "SDF Plane",
		category: "Camera",
		icon: "mdi mdi-axis-z-arrow",
		inputs: [
			{ key: "point", label: "Point", type: "vec3", default: "vec3(0.0)" },
			{ key: "height", label: "Height", type: "float", default: "0.0" },
		],
		outputs: [{ key: "distance", label: "Distance", type: "float" }],
		compile: (ins, outs) => [`${outs.distance} = ${ins.point}.y - ${ins.height};`],
	},
	{
		id: "raymarch_sphere",
		name: "Raymarch Sphere",
		category: "Camera",
		icon: "mdi mdi-ray-end",
		inputs: [
			{ key: "origin", label: "Origin", type: "vec3", default: "vec3(0.0)" },
			{ key: "direction", label: "Direction", type: "vec3", default: "vec3(0.0, 0.0, -1.0)" },
			{ key: "center", label: "Center", type: "vec3", default: "vec3(0.0)" },
			{ key: "radius", label: "Radius", type: "float", default: "1.0" },
			{ key: "maxDistance", label: "Max Distance", type: "float", default: "20.0" },
		],
		outputs: [
			{ key: "depth", label: "Depth", type: "float" },
			{ key: "hit", label: "Hit", type: "float" },
		],
		compile: (ins, outs) => [
			`${outs.depth} = 0.0;`,
			`${outs.hit} = 0.0;`,
			`for (int ${outs.depth}_i = 0; ${outs.depth}_i < 64; ${outs.depth}_i++) {`,
			`\tvec3 ${outs.depth}_p = ${ins.origin} + normalize(${ins.direction}) * ${outs.depth};`,
			`\tfloat ${outs.depth}_d = length(${outs.depth}_p - ${ins.center}) - ${ins.radius};`,
			`\tif (${outs.depth}_d < 0.001) { ${outs.hit} = 1.0; break; }`,
			`\t${outs.depth} += ${outs.depth}_d;`,
			`\tif (${outs.depth} > ${ins.maxDistance}) break;`,
			`}`,
		],
	},
	{
		id: "depth_fade",
		name: "Depth Fade",
		category: "Camera",
		icon: "mdi mdi-gradient-vertical",
		inputs: [
			{ key: "depth", label: "Depth", type: "float", default: "0.0" },
			{ key: "near", label: "Near", type: "float", default: "0.0" },
			{ key: "far", label: "Far", type: "float", default: "10.0" },
		],
		outputs: [{ key: "factor", label: "Factor", type: "float" }],
		compile: (ins, outs) => [`${outs.factor} = smoothstep(${ins.near}, max(${ins.far}, ${ins.near} + 0.0001), ${ins.depth});`],
	},

	// ── Output ──
	{
		id: "fragment_output",
		name: "Fragment Output",
		category: "Output",
		icon: "mdi mdi-export",
		inputs: [
			{ key: "color", label: "Color", type: "vec3", default: "vec3(0.0)" },
			{ key: "alpha", label: "Alpha", type: "float", default: "1.0" },
		],
		outputs: [],
		compile: (ins) => [
			`gl_FragColor = vec4(${ins.color}, ${ins.alpha});`,
		],
	},
]

export const SHADER_NODE_DEF_MAP = new Map(SHADER_NODE_DEFS.map((d) => [d.id, d]))

export const SHADER_NODE_CATEGORIES = [...new Set(SHADER_NODE_DEFS.map((d) => d.category))]

const SHADER_UNIFORM_PARAMETER_NODE_IDS = new Set(["uniform_float", "uniform_vec2", "uniform_vec3"])

// ─── GLSL Code Generation ────────────────────────────────────────────

export function getShaderPortDef(graph: ShaderGraph, nodeId: string, portKey: string, kind: "in" | "out"): ShaderPortDef | undefined {
	const node = graph.nodes.find((item) => item.id === nodeId)
	if (!node) return undefined
	const def = SHADER_NODE_DEF_MAP.get(node.defId)
	if (!def) return undefined
	const ports = kind === "in" ? def.inputs : def.outputs
	return ports.find((port) => port.key === portKey)
}

export function areShaderTypesCompatible(from: GlslType, to: GlslType): boolean {
	return from === to
}

function sortShaderGraph(graph: ShaderGraph) {
	const nodeIds = new Set(graph.nodes.map((node) => node.id))
	const inDegree = new Map<string, number>()
	const adjacency = new Map<string, string[]>()
	for (const node of graph.nodes) {
		inDegree.set(node.id, 0)
		adjacency.set(node.id, [])
	}
	for (const wire of graph.wires) {
		if (!nodeIds.has(wire.fromNode) || !nodeIds.has(wire.toNode)) continue
		adjacency.get(wire.fromNode)?.push(wire.toNode)
		inDegree.set(wire.toNode, (inDegree.get(wire.toNode) ?? 0) + 1)
	}

	const queue = graph.nodes.filter((node) => (inDegree.get(node.id) ?? 0) === 0).map((node) => node.id)
	const sorted: string[] = []
	while (queue.length > 0) {
		const nodeId = queue.shift()!
		sorted.push(nodeId)
		for (const neighbor of adjacency.get(nodeId) ?? []) {
			const deg = (inDegree.get(neighbor) ?? 1) - 1
			inDegree.set(neighbor, deg)
			if (deg === 0) queue.push(neighbor)
		}
	}

	return sorted
}

export function shaderGraphHasCycle(graph: ShaderGraph): boolean {
	return sortShaderGraph(graph).length !== graph.nodes.length
}

export function wouldCreateShaderGraphCycle(graph: ShaderGraph, fromNode: string, toNode: string): boolean {
	if (fromNode === toNode) return true
	return shaderGraphHasCycle({
		...graph,
		wires: [
			...graph.wires,
			{ id: "__candidate", fromNode, fromPort: "", toNode, toPort: "" },
		],
	})
}

export function validateShaderGraph(graph: ShaderGraph): string[] {
	const errors: string[] = []
	const nodeMap = new Map(graph.nodes.map((node) => [node.id, node]))
	const outputNodes = graph.nodes.filter((node) => node.defId === "fragment_output")

	for (const node of graph.nodes) {
		if (!SHADER_NODE_DEF_MAP.has(node.defId)) {
			errors.push(`Node ${node.id} uses unknown shader node type "${node.defId}".`)
		}
	}

	const uniformNames = new Set<string>()
	for (const node of graph.nodes) {
		if (!SHADER_UNIFORM_PARAMETER_NODE_IDS.has(node.defId)) continue
		const name = getUniformName(node)
		if (uniformNames.has(name)) {
			errors.push(`Uniform name "${name}" is used by multiple parameter nodes.`)
		}
		uniformNames.add(name)
	}

	if (graph.outputNodeId) {
		const outputNode = nodeMap.get(graph.outputNodeId)
		if (!outputNode) errors.push(`Shader graph output node "${graph.outputNodeId}" is missing.`)
		else if (outputNode.defId !== "fragment_output") errors.push(`Shader graph output node "${graph.outputNodeId}" is not a Fragment Output node.`)
	} else if (outputNodes.length === 0) {
		errors.push("Shader graph is missing a Fragment Output node.")
	} else if (outputNodes.length > 1) {
		errors.push("Shader graph has multiple Fragment Output nodes. Pick one output node before compiling.")
	}

	const inputTargets = new Set<string>()
	for (const wire of graph.wires) {
		const fromNode = nodeMap.get(wire.fromNode)
		const toNode = nodeMap.get(wire.toNode)
		if (!fromNode) {
			errors.push(`Wire ${wire.id} starts at missing node "${wire.fromNode}".`)
			continue
		}
		if (!toNode) {
			errors.push(`Wire ${wire.id} ends at missing node "${wire.toNode}".`)
			continue
		}

		const fromPort = getShaderPortDef(graph, wire.fromNode, wire.fromPort, "out")
		const toPort = getShaderPortDef(graph, wire.toNode, wire.toPort, "in")
		if (!fromPort) errors.push(`Wire ${wire.id} starts at missing output port "${wire.fromNode}:${wire.fromPort}".`)
		if (!toPort) errors.push(`Wire ${wire.id} ends at missing input port "${wire.toNode}:${wire.toPort}".`)
		if (fromPort && toPort && !areShaderTypesCompatible(fromPort.type, toPort.type)) {
			errors.push(`Wire ${wire.id} connects incompatible types: ${fromPort.type} -> ${toPort.type}.`)
		}

		const inputKey = `${wire.toNode}:${wire.toPort}`
		if (inputTargets.has(inputKey)) {
			errors.push(`Input port "${inputKey}" has multiple incoming wires.`)
		}
		inputTargets.add(inputKey)
	}

	if (shaderGraphHasCycle(graph)) {
		errors.push("Shader graph contains a cycle.")
	}

	return errors
}

function glslTypeDefault(type: GlslType): string {
	switch (type) {
		case "float": return "0.0"
		case "vec2": return "vec2(0.0)"
		case "vec3": return "vec3(0.0)"
		case "vec4": return "vec4(0.0, 0.0, 0.0, 1.0)"
	}
}

function getConstantNodeValue(node: ShaderNodeInstance, type: GlslType, fallback: string) {
	const value = node.inputDefaults?.value
	if (typeof value === "number" && Number.isFinite(value)) return String(value)
	if (typeof value === "string" && value.trim()) return value.trim()
	return fallback || glslTypeDefault(type)
}

const BUILT_IN_UNIFORMS = new Set([
	"u_resolution",
	"u_time",
	"u_accent",
	"u_secondary",
	"u_intensity",
	"u_speed",
	"u_camera_position",
	"u_camera_target",
	"u_mouse",
])

function getUniformName(node: ShaderNodeInstance) {
	const rawName = typeof node.inputDefaults?.name === "string" ? node.inputDefaults.name : ""
	const fallback = `parameter_${node.id}`
	const safe = (rawName.trim() || fallback).replace(/[^a-zA-Z0-9_]/g, "_").replace(/^[^a-zA-Z_]+/, "")
	const base = safe || fallback
	const name = base.startsWith("u_") ? base : `u_${base}`
	return BUILT_IN_UNIFORMS.has(name) ? `${name}_custom` : name
}

function parseVec3Literal(value: string): [number, number, number] {
	const source = value.match(/vec3\s*\(([^)]*)\)/)?.[1] ?? value
	const parts = source.match(/[-+]?\d*\.?\d+/g)?.map(Number) ?? []
	return [
		Number.isFinite(parts[0]) ? parts[0] : 1,
		Number.isFinite(parts[1]) ? parts[1] : 1,
		Number.isFinite(parts[2]) ? parts[2] : 1,
	]
}

function parseVec2Literal(value: string): [number, number] {
	const source = value.match(/vec2\s*\(([^)]*)\)/)?.[1] ?? value
	const parts = source.match(/[-+]?\d*\.?\d+/g)?.map(Number) ?? []
	return [
		Number.isFinite(parts[0]) ? parts[0] : 0,
		Number.isFinite(parts[1]) ? parts[1] : 0,
	]
}

export function collectShaderUniformDefaults(graph: ShaderGraph): ShaderUniformValueMap {
	const uniforms: ShaderUniformValueMap = {}
	for (const node of graph.nodes) {
		if (node.defId === "uniform_float") {
			const value = Number(getConstantNodeValue(node, "float", "1.0"))
			uniforms[getUniformName(node)] = Number.isFinite(value) ? value : 1
		}
		if (node.defId === "uniform_vec2") {
			uniforms[getUniformName(node)] = parseVec2Literal(getConstantNodeValue(node, "vec2", "vec2(0.0, 0.0)"))
		}
		if (node.defId === "uniform_vec3") {
			uniforms[getUniformName(node)] = parseVec3Literal(getConstantNodeValue(node, "vec3", "vec3(1.0, 1.0, 1.0)"))
		}
	}
	return uniforms
}

function cloneShaderNode(node: ShaderNodeInstance): ShaderNodeInstance {
	return {
		...node,
		inputDefaults: node.inputDefaults ? { ...node.inputDefaults } : undefined,
	}
}

export function createShaderNodePreviewGraph(graph: ShaderGraph, nodeId: string): ShaderGraph | undefined {
	const node = graph.nodes.find((item) => item.id === nodeId)
	if (!node) return undefined
	const def = SHADER_NODE_DEF_MAP.get(node.defId)
	if (!def) return undefined
	if (node.defId === "fragment_output") {
		return {
			nodes: graph.nodes.map(cloneShaderNode),
			wires: graph.wires.map((wire) => ({ ...wire })),
			outputNodeId: node.id,
		}
	}

	const previewPort =
		def.outputs.find((port) => port.type === "vec3") ??
		def.outputs.find((port) => port.type === "float") ??
		def.outputs.find((port) => port.type === "vec2")
	if (!previewPort) return undefined

	const baseNodes = graph.nodes
		.filter((item) => item.defId !== "fragment_output")
		.map(cloneShaderNode)
	const baseNodeIds = new Set(baseNodes.map((item) => item.id))
	const baseWires = graph.wires
		.filter((wire) => baseNodeIds.has(wire.fromNode) && baseNodeIds.has(wire.toNode))
		.map((wire) => ({ ...wire }))
	const outputId = `__preview_${node.id}_output`

	if (previewPort.type === "vec3") {
		return {
			nodes: [
				...baseNodes,
				{ id: outputId, defId: "fragment_output", x: node.x + 240, y: node.y },
			],
			wires: [
				...baseWires,
				{ id: `${node.id}:${previewPort.key}->${outputId}:color`, fromNode: node.id, fromPort: previewPort.key, toNode: outputId, toPort: "color" },
			],
			outputNodeId: outputId,
		}
	}

	const composeId = `__preview_${node.id}_color`
	const nodes = [
		...baseNodes,
		{ id: composeId, defId: "vec3_compose", x: node.x + 240, y: node.y },
		{ id: outputId, defId: "fragment_output", x: node.x + 480, y: node.y },
	]
	const wires = [
		...baseWires,
		{ id: `${composeId}:result->${outputId}:color`, fromNode: composeId, fromPort: "result", toNode: outputId, toPort: "color" },
	]

	if (previewPort.type === "float") {
		wires.push(
			{ id: `${node.id}:${previewPort.key}->${composeId}:x`, fromNode: node.id, fromPort: previewPort.key, toNode: composeId, toPort: "x" },
			{ id: `${node.id}:${previewPort.key}->${composeId}:y`, fromNode: node.id, fromPort: previewPort.key, toNode: composeId, toPort: "y" },
			{ id: `${node.id}:${previewPort.key}->${composeId}:z`, fromNode: node.id, fromPort: previewPort.key, toNode: composeId, toPort: "z" }
		)
	} else {
		const splitId = `__preview_${node.id}_split`
		nodes.splice(nodes.length - 2, 0, { id: splitId, defId: "vec2_split", x: node.x + 240, y: node.y })
		wires.push(
			{ id: `${node.id}:${previewPort.key}->${splitId}:v`, fromNode: node.id, fromPort: previewPort.key, toNode: splitId, toPort: "v" },
			{ id: `${splitId}:x->${composeId}:x`, fromNode: splitId, fromPort: "x", toNode: composeId, toPort: "x" },
			{ id: `${splitId}:y->${composeId}:y`, fromNode: splitId, fromPort: "y", toNode: composeId, toPort: "y" }
		)
	}

	return { nodes, wires, outputNodeId: outputId }
}

const SHADER_NOISE_GLSL = `float sr_hash21(vec2 p) {
\tp = fract(p * vec2(123.34, 456.21));
\tp += dot(p, p + 45.32);
\treturn fract(p.x * p.y);
}

vec2 sr_hash22(vec2 p) {
\tfloat n = sr_hash21(p);
\treturn fract(vec2(n, n + 0.37) * vec2(269.5, 183.3));
}

float sr_value_noise(vec2 p) {
\tvec2 i = floor(p);
\tvec2 f = fract(p);
\tvec2 u = f * f * (3.0 - 2.0 * f);
\tfloat a = sr_hash21(i);
\tfloat b = sr_hash21(i + vec2(1.0, 0.0));
\tfloat c = sr_hash21(i + vec2(0.0, 1.0));
\tfloat d = sr_hash21(i + vec2(1.0, 1.0));
\treturn mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float sr_perlin_noise(vec2 p) {
\tvec2 i = floor(p);
\tvec2 f = fract(p);
\tvec2 u = f * f * (3.0 - 2.0 * f);
\tvec2 ga = normalize(sr_hash22(i) * 2.0 - 1.0);
\tvec2 gb = normalize(sr_hash22(i + vec2(1.0, 0.0)) * 2.0 - 1.0);
\tvec2 gc = normalize(sr_hash22(i + vec2(0.0, 1.0)) * 2.0 - 1.0);
\tvec2 gd = normalize(sr_hash22(i + vec2(1.0, 1.0)) * 2.0 - 1.0);
\tfloat a = dot(ga, f);
\tfloat b = dot(gb, f - vec2(1.0, 0.0));
\tfloat c = dot(gc, f - vec2(0.0, 1.0));
\tfloat d = dot(gd, f - vec2(1.0, 1.0));
\treturn mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float sr_fbm(vec2 p, float octaves, float lacunarity, float gain) {
\tfloat value = 0.0;
\tfloat amplitude = 0.5;
\tfloat norm = 0.0;
\tfor (int i = 0; i < 8; i++) {
\t\tif (float(i) >= octaves) break;
\t\tvalue += amplitude * sr_value_noise(p);
\t\tnorm += amplitude;
\t\tp *= lacunarity;
\t\tamplitude *= gain;
\t}
\treturn norm > 0.0 ? value / norm : 0.0;
}

float sr_voronoi(vec2 p, float jitter) {
\tvec2 i = floor(p);
\tvec2 f = fract(p);
\tfloat nearest = 8.0;
\tfor (int y = -1; y <= 1; y++) {
\t\tfor (int x = -1; x <= 1; x++) {
\t\t\tvec2 cell = vec2(float(x), float(y));
\t\t\tvec2 point = cell + mix(vec2(0.5), sr_hash22(i + cell), clamp(jitter, 0.0, 1.0)) - f;
\t\t\tnearest = min(nearest, dot(point, point));
\t\t}
\t}
\treturn clamp(sqrt(nearest), 0.0, 1.0);
}

vec2 sr_domain_warp(vec2 p, float strength) {
\tfloat x = sr_fbm(p + vec2(17.2, 9.1), 4.0, 2.0, 0.5);
\tfloat y = sr_fbm(p + vec2(-8.3, 23.7), 4.0, 2.0, 0.5);
\treturn p + (vec2(x, y) * 2.0 - 1.0) * strength;
}`

export function compileShaderGraph(graph: ShaderGraph): { glsl: string; errors: string[] } {
	const errors = validateShaderGraph(graph)
	if (errors.length) return { glsl: "", errors }

	const nodeMap = new Map(graph.nodes.map((n) => [n.id, n]))
	const defMap = SHADER_NODE_DEF_MAP
	const sorted = sortShaderGraph(graph)

	// Build variable names and collect GLSL lines
	const varNames = new Map<string, Map<string, string>>() // nodeId → portKey → varName
	let varCounter = 0

	for (const nodeId of sorted) {
		const node = nodeMap.get(nodeId)!
		const def = defMap.get(node.defId)
		if (!def) {
			errors.push(`Unknown node type: ${node.defId}`)
			continue
		}

		// Create output variable names
		const outputVars = new Map<string, string>()
		for (const port of def.outputs) {
			const name = `v${varCounter++}_${nodeId.replace(/[^a-zA-Z0-9]/g, "_")}_${port.key}`
			outputVars.set(port.key, name)
		}
		varNames.set(nodeId, outputVars)
	}

	// Wire map: toNode:toPort → fromNode:fromPort
	const wireMap = new Map<string, { fromNode: string; fromPort: string }>()
	for (const wire of graph.wires) {
		wireMap.set(`${wire.toNode}:${wire.toPort}`, { fromNode: wire.fromNode, fromPort: wire.fromPort })
	}

	// Generate code
	const bodyLines: string[] = []
	const uniformLines = new Set<string>()

	for (const nodeId of sorted) {
		const node = nodeMap.get(nodeId)!
		const def = defMap.get(node.defId)!

		// Resolve input variable names
		const ins: Record<string, string> = {}
		for (const port of def.inputs) {
			const wireKey = `${nodeId}:${port.key}`
			const wire = wireMap.get(wireKey)
			if (wire) {
				const sourceVars = varNames.get(wire.fromNode)
				ins[port.key] = sourceVars?.get(wire.fromPort) ?? (port.default ?? glslTypeDefault(port.type))
			} else {
				// Use node instance default or port default
				const instanceDefault = node.inputDefaults?.[port.key]
				if (instanceDefault != null) {
					ins[port.key] = String(instanceDefault)
				} else {
					ins[port.key] = port.default ?? glslTypeDefault(port.type)
				}
			}
		}

		// Resolve output variable names
		const outs: Record<string, string> = {}
		const nodeVars = varNames.get(nodeId)!
		for (const port of def.outputs) {
			outs[port.key] = nodeVars.get(port.key)!
		}

		// Declare output variables
		for (const port of def.outputs) {
			const varName = nodeVars.get(port.key)!
			bodyLines.push(`\t${port.type} ${varName};`)
		}

		// Emit node body
		let lines: string[]
		if (node.defId === "float_const") {
			lines = [`${outs.value} = ${getConstantNodeValue(node, "float", "1.0")};`]
		} else if (node.defId === "vec3_const") {
			lines = [`${outs.value} = ${getConstantNodeValue(node, "vec3", "vec3(1.0, 1.0, 1.0)")};`]
		} else if (node.defId === "uniform_float") {
			const uniformName = getUniformName(node)
			uniformLines.add(`uniform float ${uniformName};`)
			lines = [`${outs.value} = ${uniformName};`]
		} else if (node.defId === "uniform_vec2") {
			const uniformName = getUniformName(node)
			uniformLines.add(`uniform vec2 ${uniformName};`)
			lines = [`${outs.value} = ${uniformName};`]
		} else if (node.defId === "uniform_vec3") {
			const uniformName = getUniformName(node)
			uniformLines.add(`uniform vec3 ${uniformName};`)
			lines = [`${outs.value} = ${uniformName};`]
		} else {
			lines = def.compile(ins, outs)
		}
		for (const line of lines) {
			bodyLines.push(`\t${line}`)
		}
		bodyLines.push("")
	}

	const glsl = `precision mediump float;
uniform vec2 u_resolution;
uniform float u_time;
uniform vec3 u_accent;
uniform vec3 u_secondary;
uniform float u_intensity;
uniform float u_speed;
uniform vec3 u_camera_position;
uniform vec3 u_camera_target;
uniform vec2 u_mouse;
${[...uniformLines].join("\n")}

${SHADER_NOISE_GLSL}

void main() {
${bodyLines.join("\n")}
}
`

	return { glsl, errors }
}
