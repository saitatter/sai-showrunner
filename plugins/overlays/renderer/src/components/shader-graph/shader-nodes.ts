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

export function validateShaderGraph(graph: ShaderGraph): string[] {
	const errors: string[] = []
	const nodeMap = new Map(graph.nodes.map((node) => [node.id, node]))
	const outputNodes = graph.nodes.filter((node) => node.defId === "fragment_output")

	for (const node of graph.nodes) {
		if (!SHADER_NODE_DEF_MAP.has(node.defId)) {
			errors.push(`Node ${node.id} uses unknown shader node type "${node.defId}".`)
		}
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

	if (sortShaderGraph(graph).length !== graph.nodes.length) {
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
		const lines = def.compile(ins, outs)
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

void main() {
${bodyLines.join("\n")}
}
`

	return { glsl, errors }
}
