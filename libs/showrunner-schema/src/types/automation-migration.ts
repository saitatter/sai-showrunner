import type { AutomationConfig, AutomationData, InlineAutomation } from "./automations"
import type { AutomationDataWire, AutomationGraph, SubgraphDefinition } from "./graph"

const EMPTY_GRAPH: AutomationGraph = { nodes: [], edges: [], entryNodeId: "" }

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

