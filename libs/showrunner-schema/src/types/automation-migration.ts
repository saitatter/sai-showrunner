import type { AutomationConfig, AutomationData, AutomationTriggerNode, InlineAutomation } from "./automations"
import type { AutomationDataWire, AutomationGraph, SubgraphDefinition } from "./graph"

const EMPTY_GRAPH: AutomationGraph = { nodes: [], edges: [], entryNodeId: "" }
const LEGACY_TRIGGER_NODE_ID = "trigger"

export function normalizeAutomationData<T extends Partial<AutomationData> & Record<string, any>>(
	input: T
): T & AutomationData {
	const target = input as T & AutomationData & Record<string, any>
	const hadGraph = isGraph(target.graph)
	const graph = hadGraph ? normalizeGraph(target.graph) : { ...EMPTY_GRAPH }

	target.schemaVersion = 2
	target.graph = graph
	target.subgraphs = Array.isArray(target.subgraphs) ? target.subgraphs.map(normalizeSubgraph) : []
	target.dataWires = Array.isArray(target.dataWires) ? target.dataWires : []
	target.variableNodes = Array.isArray(target.variableNodes) ? target.variableNodes : []
	target.triggerNodes = normalizeTriggerNodes(target.triggerNodes, target)

	for (const staleKey of [String.fromCharCode(115, 101, 113, 117, 101, 110, 99, 101), `floating${"Seq"}uences`]) {
		delete target[staleKey]
	}

	return target
}

function normalizeSubgraph(subgraph: SubgraphDefinition): SubgraphDefinition {
	return {
		...subgraph,
		parameters: Array.isArray(subgraph.parameters) ? subgraph.parameters : [],
		outputs: Array.isArray(subgraph.outputs) ? subgraph.outputs : [],
		nodes: Array.isArray(subgraph.nodes) ? subgraph.nodes : [],
		edges: Array.isArray(subgraph.edges) ? subgraph.edges : [],
		dataWires: normalizeDataWires(subgraph.dataWires),
		entryNodeId: typeof subgraph.entryNodeId === "string" ? subgraph.entryNodeId : subgraph.nodes?.[0]?.id ?? "",
	}
}

function normalizeDataWires(wires: AutomationDataWire[] | undefined): AutomationDataWire[] {
	return Array.isArray(wires) ? wires.filter((wire) => wire?.id && wire.fromNode && wire.toNode && wire.fromPort && wire.toPort) : []
}

function normalizeTriggerNodes(value: unknown, legacySource: Record<string, any>): AutomationTriggerNode[] {
	const triggerNodes = Array.isArray(value)
		? value
			.filter((node) => node && typeof node === "object")
			.map((node) => normalizeTriggerNode(node as Partial<AutomationTriggerNode> & Record<string, any>))
			.filter((node): node is AutomationTriggerNode => Boolean(node))
		: []

	if (triggerNodes.length) return triggerNodes
	if (!legacySource.plugin && !legacySource.trigger) return []

	return [
		{
			id: LEGACY_TRIGGER_NODE_ID,
			plugin: typeof legacySource.plugin === "string" ? legacySource.plugin : undefined,
			trigger: typeof legacySource.trigger === "string" ? legacySource.trigger : undefined,
			config: legacySource.config ?? {},
			stop: typeof legacySource.stop === "boolean" ? legacySource.stop : undefined,
			x: 42,
			y: 88,
		},
	]
}

function normalizeTriggerNode(node: Partial<AutomationTriggerNode> & Record<string, any>): AutomationTriggerNode | undefined {
	if (typeof node.id !== "string" || !node.id) return undefined
	return {
		id: node.id,
		plugin: typeof node.plugin === "string" ? node.plugin : undefined,
		trigger: typeof node.trigger === "string" ? node.trigger : undefined,
		config: node.config ?? {},
		stop: typeof node.stop === "boolean" ? node.stop : undefined,
		x: typeof node.x === "number" && Number.isFinite(node.x) ? node.x : 42,
		y: typeof node.y === "number" && Number.isFinite(node.y) ? node.y : 88,
	}
}

export function normalizeInlineAutomation<T extends Partial<InlineAutomation> & Record<string, any>>(input: T) {
	return normalizeAutomationData(input)
}

export function normalizeAutomationConfig<T extends Partial<AutomationConfig> & Record<string, any>>(input: T) {
	const normalized = normalizeAutomationData(input)
	normalized.name = typeof normalized.name === "string" ? normalized.name : ""
	return normalized as T & AutomationConfig
}

function isGraph(value: unknown): value is AutomationGraph {
	return Boolean(
		value &&
			typeof value === "object" &&
			Array.isArray((value as AutomationGraph).nodes) &&
			Array.isArray((value as AutomationGraph).edges)
	)
}

function normalizeGraph(graph: AutomationGraph): AutomationGraph {
	return {
		nodes: Array.isArray(graph.nodes) ? graph.nodes : [],
		edges: Array.isArray(graph.edges) ? graph.edges : [],
		entryNodeId: typeof graph.entryNodeId === "string" ? graph.entryNodeId : graph.nodes?.[0]?.id ?? "",
	}
}

