import type { ShaderGraph, ShaderNodeInstance, ShaderUniformValueMap, ShaderWire } from "./shader-nodes"

export interface ShaderLayerGraphConfig {
	preset?: string
	customFragmentShader?: string
	shaderGraph?: unknown
	shaderUniforms?: ShaderUniformValueMap
}

const DEFAULT_SHADER_GRAPH: ShaderGraph = {
	nodes: [
		{ id: "output", defId: "fragment_output", x: 600, y: 200 },
		{ id: "uv", defId: "uv", x: 50, y: 200 },
	],
	wires: [],
	outputNodeId: "output",
}

export function createDefaultShaderGraph(): ShaderGraph {
	return cloneShaderGraph(DEFAULT_SHADER_GRAPH)
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
		outputNodeId: graph.outputNodeId,
	}
}

export function normalizeShaderGraph(value: unknown): ShaderGraph {
	if (!isRecord(value) || !Array.isArray(value.nodes) || !Array.isArray(value.wires)) {
		return createDefaultShaderGraph()
	}

	const nodes = value.nodes.flatMap((node): ShaderNodeInstance[] => {
		if (!isRecord(node) || typeof node.id !== "string" || typeof node.defId !== "string") return []
		return [{
			id: node.id,
			defId: node.defId,
			x: Number.isFinite(node.x) ? Number(node.x) : 0,
			y: Number.isFinite(node.y) ? Number(node.y) : 0,
			inputDefaults: isRecord(node.inputDefaults) ? { ...node.inputDefaults } : undefined,
		}]
	})

	const nodeIds = new Set(nodes.map((node) => node.id))
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
	return { nodes, wires, outputNodeId }
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

export function applyCompiledShaderGraph(config: ShaderLayerGraphConfig, graph: ShaderGraph, glsl: string, uniforms: ShaderUniformValueMap = {}) {
	persistShaderGraph(config, graph)
	config.preset = "custom"
	config.customFragmentShader = glsl
	config.shaderUniforms = { ...uniforms }
}

function isRecord(value: unknown): value is Record<string, unknown> {
	return Boolean(value && typeof value === "object" && !Array.isArray(value))
}
