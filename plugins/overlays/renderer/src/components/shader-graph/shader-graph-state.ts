import type { ShaderUniformBindingMap } from "showrunner-plugin-overlays-shared"
import { getShaderUniformName, type ShaderFrame, type ShaderGraph, type ShaderNodeInstance, type ShaderUniformValueMap, type ShaderWire } from "./shader-nodes"

export interface ShaderLayerGraphConfig {
	preset?: string
	customFragmentShader?: string
	shaderGraph?: unknown
	shaderUniforms?: ShaderUniformValueMap
	shaderUniformBindings?: ShaderUniformBindingMap
}

export interface ShaderGraphStarter {
	id: string
	name: string
	description: string
}

export interface ShaderGraphClipboard {
	nodes: ShaderNodeInstance[]
	wires: ShaderWire[]
}

export interface ShaderGraphPasteResult {
	nodes: ShaderNodeInstance[]
	wires: ShaderWire[]
	selectedNodeIds: string[]
}

export const SHADER_GRAPH_STARTERS: ShaderGraphStarter[] = [
	{ id: "procedural-terrain", name: "Procedural Terrain", description: "FBM terrain with altitude bands and simple sunlight." },
	{ id: "nebula", name: "Nebula", description: "Warped cloud colors for atmospheric overlays." },
	{ id: "audio-reactive", name: "Audio Reactive", description: "Intensity-driven bands for music or alerts." },
	{ id: "energy-field", name: "Energy Field", description: "Voronoi and wave-driven animated energy." },
]

const DEFAULT_SHADER_GRAPH: ShaderGraph = {
	nodes: [
		{ id: "uv", defId: "uv", x: 40, y: 180 },
		{ id: "split_uv", defId: "vec2_split", x: 260, y: 180 },
		{ id: "accent", defId: "accent_color", x: 260, y: 20 },
		{ id: "secondary", defId: "secondary_color", x: 260, y: 340 },
		{ id: "gradient", defId: "mix_color", x: 520, y: 180 },
		{ id: "output", defId: "fragment_output", x: 780, y: 190 },
	],
	wires: [
		{ id: "uv:uv->split_uv:v", fromNode: "uv", fromPort: "uv", toNode: "split_uv", toPort: "v" },
		{ id: "accent:color->gradient:a", fromNode: "accent", fromPort: "color", toNode: "gradient", toPort: "a" },
		{ id: "secondary:color->gradient:b", fromNode: "secondary", fromPort: "color", toNode: "gradient", toPort: "b" },
		{ id: "split_uv:x->gradient:t", fromNode: "split_uv", fromPort: "x", toNode: "gradient", toPort: "t" },
		{ id: "gradient:result->output:color", fromNode: "gradient", fromPort: "result", toNode: "output", toPort: "color" },
	],
	outputNodeId: "output",
}

export function createDefaultShaderGraph(): ShaderGraph {
	return cloneShaderGraph(DEFAULT_SHADER_GRAPH)
}

export function createShaderGraphStarter(id: string): ShaderGraph {
	switch (id) {
		case "procedural-terrain":
			return cloneShaderGraph(PROCEDURAL_TERRAIN_GRAPH)
		case "nebula":
			return cloneShaderGraph(NEBULA_GRAPH)
		case "audio-reactive":
			return cloneShaderGraph(AUDIO_REACTIVE_GRAPH)
		case "energy-field":
			return cloneShaderGraph(ENERGY_FIELD_GRAPH)
		default:
			return createDefaultShaderGraph()
	}
}

export function cloneShaderGraph(graph: ShaderGraph): ShaderGraph {
	return {
		nodes: graph.nodes.map((node) => ({
			id: node.id,
			defId: node.defId,
			x: Number.isFinite(node.x) ? node.x : 0,
			y: Number.isFinite(node.y) ? node.y : 0,
			inputDefaults: node.inputDefaults ? { ...node.inputDefaults } : undefined,
		})),
		wires: graph.wires.map((wire) => ({
			id: wire.id,
			fromNode: wire.fromNode,
			fromPort: wire.fromPort,
			toNode: wire.toNode,
			toPort: wire.toPort,
		})),
		frames: graph.frames?.map((frame) => ({
			id: frame.id,
			title: frame.title,
			color: frame.color,
			x: Number.isFinite(frame.x) ? frame.x : 0,
			y: Number.isFinite(frame.y) ? frame.y : 0,
			width: Number.isFinite(frame.width) ? frame.width : 360,
			height: Number.isFinite(frame.height) ? frame.height : 220,
			nodeIds: frame.nodeIds ? [...frame.nodeIds] : undefined,
		})),
		outputNodeId: graph.outputNodeId,
	}
}

export function copyShaderGraphSelection(graph: ShaderGraph, selectedNodeIds: Iterable<string>): ShaderGraphClipboard | undefined {
	const selectedIds = new Set(selectedNodeIds)
	if (!selectedIds.size) return undefined
	const nodes = graph.nodes
		.filter((node) => selectedIds.has(node.id))
		.map((node) => ({
			id: node.id,
			defId: node.defId,
			x: node.x,
			y: node.y,
			inputDefaults: node.inputDefaults ? { ...node.inputDefaults } : undefined,
		}))
	if (!nodes.length) return undefined
	const wires = graph.wires
		.filter((wire) => selectedIds.has(wire.fromNode) && selectedIds.has(wire.toNode))
		.map((wire) => ({ ...wire }))
	return { nodes, wires }
}

export function pasteShaderGraphSelection(
	clipboard: ShaderGraphClipboard,
	createNodeId: () => string,
	offset = 36
): ShaderGraphPasteResult {
	const idMap = new Map<string, string>()
	const nodes = clipboard.nodes.map((node) => {
		const id = createNodeId()
		idMap.set(node.id, id)
		return {
			id,
			defId: node.defId,
			x: node.x + offset,
			y: node.y + offset,
			inputDefaults: node.inputDefaults ? { ...node.inputDefaults } : undefined,
		}
	})
	const wires = clipboard.wires.flatMap((wire) => {
		const fromNode = idMap.get(wire.fromNode)
		const toNode = idMap.get(wire.toNode)
		if (!fromNode || !toNode) return []
		return [{
			id: `${fromNode}:${wire.fromPort}->${toNode}:${wire.toPort}`,
			fromNode,
			fromPort: wire.fromPort,
			toNode,
			toPort: wire.toPort,
		}]
	})
	return { nodes, wires, selectedNodeIds: nodes.map((node) => node.id) }
}

export function normalizeShaderGraph(value: unknown): ShaderGraph {
	if (!isRecord(value) || !Array.isArray(value.nodes) || !Array.isArray(value.wires)) {
		return createDefaultShaderGraph()
	}

	const nodes = value.nodes.flatMap((node): ShaderNodeInstance[] => {
		if (!isRecord(node) || typeof node.id !== "string" || typeof node.defId !== "string") return []
		if (node.defId === "comment_frame") return []
		return [{
			id: node.id,
			defId: node.defId,
			x: Number.isFinite(node.x) ? Number(node.x) : 0,
			y: Number.isFinite(node.y) ? Number(node.y) : 0,
			inputDefaults: isRecord(node.inputDefaults) ? { ...node.inputDefaults } : undefined,
		}]
	})

	const nodeIds = new Set(nodes.map((node) => node.id))
	const migratedCommentFrames = value.nodes.flatMap((node): ShaderFrame[] => {
		if (!isRecord(node) || node.defId !== "comment_frame" || typeof node.id !== "string") return []
		const defaults = isRecord(node.inputDefaults) ? node.inputDefaults : {}
		const title = typeof defaults.title === "string" && defaults.title.trim()
			? defaults.title.trim()
			: typeof defaults.note === "string" && defaults.note.trim()
				? defaults.note.trim().slice(0, 40)
				: "Frame"
		return [{
			id: `frame:${node.id}`,
			title,
			color: "#7c4dff",
			x: Number.isFinite(node.x) ? Number(node.x) : 0,
			y: Number.isFinite(node.y) ? Number(node.y) : 0,
			width: 360,
			height: 220,
		}]
	})
	const frames = Array.isArray(value.frames)
		? value.frames.flatMap((frame): ShaderFrame[] => {
			if (!isRecord(frame) || typeof frame.id !== "string") return []
			const nodeIdsInFrame = Array.isArray(frame.nodeIds)
				? frame.nodeIds.filter((nodeId): nodeId is string => typeof nodeId === "string" && nodeIds.has(nodeId))
				: undefined
			return [{
				id: frame.id,
				title: typeof frame.title === "string" && frame.title.trim() ? frame.title : "Frame",
				color: typeof frame.color === "string" && frame.color.trim() ? frame.color : "#7c4dff",
				x: Number.isFinite(frame.x) ? Number(frame.x) : 0,
				y: Number.isFinite(frame.y) ? Number(frame.y) : 0,
				width: Number.isFinite(frame.width) ? Math.max(160, Number(frame.width)) : 360,
				height: Number.isFinite(frame.height) ? Math.max(96, Number(frame.height)) : 220,
				nodeIds: nodeIdsInFrame?.length ? nodeIdsInFrame : undefined,
			}]
		})
		: undefined
	const normalizedFrames = [...(frames ?? []), ...migratedCommentFrames]
	const wires = value.wires.flatMap((wire): ShaderWire[] => {
		if (
			!isRecord(wire) ||
			typeof wire.id !== "string" ||
			typeof wire.fromNode !== "string" ||
			typeof wire.fromPort !== "string" ||
			typeof wire.toNode !== "string" ||
			typeof wire.toPort !== "string"
		) return []
		if (!nodeIds.has(wire.fromNode) || !nodeIds.has(wire.toNode)) return []
		return [{
			id: wire.id,
			fromNode: wire.fromNode,
			fromPort: wire.fromPort,
			toNode: wire.toNode,
			toPort: wire.toPort,
		}]
	})

	if (!nodes.length) return createDefaultShaderGraph()

	const outputNodeId = typeof value.outputNodeId === "string" ? value.outputNodeId : nodes.find((node) => node.defId === "fragment_output")?.id
	return { nodes, wires, frames: normalizedFrames.length ? normalizedFrames : undefined, outputNodeId }
}

export function hasLegacyCustomShaderWithoutGraph(config: ShaderLayerGraphConfig | undefined): boolean {
	return Boolean(
		config?.preset === "custom" &&
		typeof config.customFragmentShader === "string" &&
		config.customFragmentShader.trim() &&
		!config.shaderGraph
	)
}

export function persistShaderGraph(config: ShaderLayerGraphConfig, graph: ShaderGraph) {
	config.shaderGraph = cloneShaderGraph(graph)
}

export function applyCompiledShaderGraph(
	config: ShaderLayerGraphConfig,
	graph: ShaderGraph,
	glsl: string,
	uniforms: ShaderUniformValueMap = {},
	bindings: ShaderUniformBindingMap = {}
) {
	persistShaderGraph(config, graph)
	config.preset = "custom"
	config.customFragmentShader = glsl
	config.shaderUniforms = { ...uniforms }
	config.shaderUniformBindings = { ...bindings }
}

export function collectShaderUniformBindings(graph: ShaderGraph): ShaderUniformBindingMap {
	const bindings: ShaderUniformBindingMap = {}
	for (const node of graph.nodes) {
		if (!["uniform_float", "uniform_vec2", "uniform_vec3"].includes(node.defId)) continue
		const source = node.inputDefaults?.bindingSource
		if (source === "config") {
			const path = String(node.inputDefaults?.bindingPath ?? "").trim()
			if (path) bindings[getShaderUniformName(node)] = { source, path }
		} else if (source === "state") {
			const plugin = String(node.inputDefaults?.bindingPlugin ?? "").trim()
			const state = String(node.inputDefaults?.bindingState ?? "").trim()
			const path = String(node.inputDefaults?.bindingPath ?? "").trim()
			if (plugin && state && path) bindings[getShaderUniformName(node)] = { source, plugin, state, path }
		}
	}
	return bindings
}

function isRecord(value: unknown): value is Record<string, unknown> {
	return Boolean(value && typeof value === "object" && !Array.isArray(value))
}

const PROCEDURAL_TERRAIN_GRAPH: ShaderGraph = {
	nodes: [
		{ id: "uv", defId: "uv", x: 40, y: 220 },
		{ id: "warp", defId: "domain_warp", x: 260, y: 180, inputDefaults: { scale: "2.2", strength: "0.22" } },
		{ id: "base", defId: "fbm_noise", x: 500, y: 160, inputDefaults: { scale: "3.5", octaves: "6.0" } },
		{ id: "detail", defId: "value_noise", x: 500, y: 340, inputDefaults: { scale: "18.0" } },
		{ id: "height", defId: "terrain_height", x: 760, y: 200, inputDefaults: { detailStrength: "0.18" } },
		{ id: "bands", defId: "altitude_bands", x: 1020, y: 180 },
		{ id: "normal", defId: "normal_from_height", x: 1020, y: 420, inputDefaults: { strength: "1.6" } },
		{ id: "sun", defId: "sun_direction", x: 1260, y: 420 },
		{ id: "light", defId: "diffuse_lighting", x: 1500, y: 220, inputDefaults: { ambient: "0.28" } },
		{ id: "output", defId: "fragment_output", x: 1740, y: 240 },
	],
	wires: [
		{ id: "uv:uv->warp:uv", fromNode: "uv", fromPort: "uv", toNode: "warp", toPort: "uv" },
		{ id: "warp:uv->base:uv", fromNode: "warp", fromPort: "uv", toNode: "base", toPort: "uv" },
		{ id: "warp:uv->detail:uv", fromNode: "warp", fromPort: "uv", toNode: "detail", toPort: "uv" },
		{ id: "base:value->height:base", fromNode: "base", fromPort: "value", toNode: "height", toPort: "base" },
		{ id: "detail:value->height:detail", fromNode: "detail", fromPort: "value", toNode: "height", toPort: "detail" },
		{ id: "height:height->bands:height", fromNode: "height", fromPort: "height", toNode: "bands", toPort: "height" },
		{ id: "height:height->normal:center", fromNode: "height", fromPort: "height", toNode: "normal", toPort: "center" },
		{ id: "height:height->normal:right", fromNode: "height", fromPort: "height", toNode: "normal", toPort: "right" },
		{ id: "height:height->normal:up", fromNode: "height", fromPort: "height", toNode: "normal", toPort: "up" },
		{ id: "bands:color->light:color", fromNode: "bands", fromPort: "color", toNode: "light", toPort: "color" },
		{ id: "normal:normal->light:normal", fromNode: "normal", fromPort: "normal", toNode: "light", toPort: "normal" },
		{ id: "sun:direction->light:lightDir", fromNode: "sun", fromPort: "direction", toNode: "light", toPort: "lightDir" },
		{ id: "light:color->output:color", fromNode: "light", fromPort: "color", toNode: "output", toPort: "color" },
	],
	outputNodeId: "output",
}

const NEBULA_GRAPH: ShaderGraph = {
	nodes: [
		{ id: "uv", defId: "uv", x: 40, y: 220 },
		{ id: "time", defId: "time", x: 40, y: 420 },
		{ id: "warp", defId: "domain_warp", x: 300, y: 220, inputDefaults: { scale: "2.8", strength: "0.35" } },
		{ id: "noise", defId: "fbm_noise", x: 560, y: 220, inputDefaults: { scale: "5.0", octaves: "6.0" } },
		{ id: "ramp", defId: "color_ramp", x: 820, y: 220, inputDefaults: { low: "vec3(0.04, 0.03, 0.12)", mid: "vec3(0.42, 0.12, 0.70)", high: "vec3(0.05, 0.75, 1.0)" } },
		{ id: "output", defId: "fragment_output", x: 1080, y: 240 },
	],
	wires: [
		{ id: "uv:uv->warp:uv", fromNode: "uv", fromPort: "uv", toNode: "warp", toPort: "uv" },
		{ id: "warp:uv->noise:uv", fromNode: "warp", fromPort: "uv", toNode: "noise", toPort: "uv" },
		{ id: "noise:value->ramp:factor", fromNode: "noise", fromPort: "value", toNode: "ramp", toPort: "factor" },
		{ id: "ramp:color->output:color", fromNode: "ramp", fromPort: "color", toNode: "output", toPort: "color" },
	],
	outputNodeId: "output",
}

const AUDIO_REACTIVE_GRAPH: ShaderGraph = {
	nodes: [
		{ id: "uv", defId: "uv", x: 40, y: 180 },
		{ id: "split", defId: "vec2_split", x: 260, y: 180 },
		{ id: "time", defId: "time", x: 260, y: 360 },
		{ id: "intensity", defId: "intensity", x: 260, y: 500 },
		{ id: "wave", defId: "wave", x: 520, y: 220, inputDefaults: { frequency: "24.0", speed: "3.0" } },
		{ id: "mix", defId: "multiply", x: 760, y: 260 },
		{ id: "gradient", defId: "gradient_color", x: 1000, y: 240 },
		{ id: "output", defId: "fragment_output", x: 1240, y: 260 },
	],
	wires: [
		{ id: "uv:uv->split:v", fromNode: "uv", fromPort: "uv", toNode: "split", toPort: "v" },
		{ id: "split:y->wave:x", fromNode: "split", fromPort: "y", toNode: "wave", toPort: "x" },
		{ id: "time:t->wave:time", fromNode: "time", fromPort: "t", toNode: "wave", toPort: "time" },
		{ id: "wave:result->mix:a", fromNode: "wave", fromPort: "result", toNode: "mix", toPort: "a" },
		{ id: "intensity:value->mix:b", fromNode: "intensity", fromPort: "value", toNode: "mix", toPort: "b" },
		{ id: "mix:result->gradient:factor", fromNode: "mix", fromPort: "result", toNode: "gradient", toPort: "factor" },
		{ id: "gradient:color->output:color", fromNode: "gradient", fromPort: "color", toNode: "output", toPort: "color" },
	],
	outputNodeId: "output",
}

const ENERGY_FIELD_GRAPH: ShaderGraph = {
	nodes: [
		{ id: "uv", defId: "uv", x: 40, y: 200 },
		{ id: "time", defId: "time", x: 40, y: 420 },
		{ id: "voronoi", defId: "voronoi_noise", x: 300, y: 180, inputDefaults: { scale: "14.0", jitter: "0.9" } },
		{ id: "split", defId: "vec2_split", x: 300, y: 380 },
		{ id: "wave", defId: "wave", x: 560, y: 360, inputDefaults: { frequency: "18.0", speed: "2.5" } },
		{ id: "mix", defId: "mix_float", x: 800, y: 240, inputDefaults: { t: "0.5" } },
		{ id: "ramp", defId: "color_ramp", x: 1040, y: 240, inputDefaults: { low: "vec3(0.0, 0.05, 0.08)", mid: "vec3(0.0, 0.8, 1.0)", high: "vec3(1.0, 1.0, 1.0)" } },
		{ id: "output", defId: "fragment_output", x: 1280, y: 260 },
	],
	wires: [
		{ id: "uv:uv->voronoi:uv", fromNode: "uv", fromPort: "uv", toNode: "voronoi", toPort: "uv" },
		{ id: "uv:uv->split:v", fromNode: "uv", fromPort: "uv", toNode: "split", toPort: "v" },
		{ id: "split:x->wave:x", fromNode: "split", fromPort: "x", toNode: "wave", toPort: "x" },
		{ id: "time:t->wave:time", fromNode: "time", fromPort: "t", toNode: "wave", toPort: "time" },
		{ id: "voronoi:distance->mix:a", fromNode: "voronoi", fromPort: "distance", toNode: "mix", toPort: "a" },
		{ id: "wave:result->mix:b", fromNode: "wave", fromPort: "result", toNode: "mix", toPort: "b" },
		{ id: "mix:result->ramp:factor", fromNode: "mix", fromPort: "result", toNode: "ramp", toPort: "factor" },
		{ id: "ramp:color->output:color", fromNode: "ramp", fromPort: "color", toNode: "output", toPort: "color" },
	],
	outputNodeId: "output",
}
