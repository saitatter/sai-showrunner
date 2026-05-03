import { nanoid } from "nanoid/non-secure"
import type { AutomationConfig, AutomationData, InlineAutomation } from "./automations"
import type { AutomationGraph, GraphEdge, GraphNode } from "./graph"

type LegacyAction = {
	id?: string
	plugin?: string
	action?: string
	config?: any
	resultMapping?: Record<string, string>
	stack?: LegacyAction[]
	offsets?: Array<{ actions?: LegacyAction[] }>
	subFlows?: Array<{ actions?: LegacyAction[] }>
}

const EMPTY_GRAPH: AutomationGraph = { nodes: [], edges: [], entryNodeId: "" }

export function normalizeAutomationData<T extends Partial<AutomationData> & Record<string, any>>(
	input: T
): T & AutomationData {
	const target = input as T & AutomationData & Record<string, any>
	const hadGraph = isGraph(target.graph)
	const graph = hadGraph ? normalizeGraph(target.graph) : graphFromLegacySequence(target.sequence)

	target.schemaVersion = 2
	target.graph = graph
	target.subgraphs = Array.isArray(target.subgraphs) ? target.subgraphs : []
	target.dataWires = Array.isArray(target.dataWires) ? target.dataWires : []
	target.variableNodes = Array.isArray(target.variableNodes) ? target.variableNodes : []

	delete target.sequence
	delete target.floatingSequences

	return target
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

function graphFromLegacySequence(sequence: { actions?: LegacyAction[] } | undefined): AutomationGraph {
	if (!sequence || !Array.isArray(sequence.actions) || sequence.actions.length === 0) {
		return { ...EMPTY_GRAPH }
	}

	const nodes: GraphNode[] = []
	const edges: GraphEdge[] = []
	let previousNodeId: string | undefined

	const appendAction = (action: LegacyAction, depth = 0) => {
		if (isStackAction(action)) {
			for (const child of action.stack) appendAction(child, depth + 1)
			return
		}

		const node = legacyActionToGraphNode(action, nodes.length, depth)
		if (!node) return

		nodes.push(node)
		if (previousNodeId) {
			edges.push({ id: `${previousNodeId}->${node.id}`, from: previousNodeId, to: node.id })
		}
		previousNodeId = node.id

		for (const offset of action.offsets ?? []) {
			for (const child of offset.actions ?? []) appendAction(child, depth + 1)
		}
		for (const flow of action.subFlows ?? []) {
			for (const child of flow.actions ?? []) appendAction(child, depth + 1)
		}
	}

	for (const action of sequence.actions) appendAction(action)

	return {
		nodes,
		edges,
		entryNodeId: nodes[0]?.id ?? "",
	}
}

function isStackAction(action: LegacyAction): action is LegacyAction & { stack: LegacyAction[] } {
	return Array.isArray(action.stack)
}

function legacyActionToGraphNode(action: LegacyAction, index: number, depth: number): Extract<GraphNode, { type: "action" }> | undefined {
	if (!action.plugin || !action.action) return undefined
	return {
		id: action.id || nanoid(),
		type: "action",
		plugin: action.plugin,
		action: action.action,
		config: action.config ?? {},
		resultMapping: action.resultMapping,
		x: 320 + index * 285,
		y: 120 + depth * 128,
	}
}
