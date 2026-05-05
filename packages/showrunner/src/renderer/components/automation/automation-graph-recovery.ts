import type {
	AutomationConfig,
	AutomationDataWire,
	AutomationGraph,
	AutomationVariableNode,
	GraphNode,
	SubgraphDefinition,
} from "showrunner-schema"
import { isCoreConversionAction } from "./coreConversionActions"

const VALID_NODE_TYPES = new Set(["action", "if", "switch", "for", "forEach", "while", "break", "continue", "return", "subgraphCall"])
const VALID_VARIABLE_TYPES = new Set(["string", "number", "boolean", "color"])

export function validateAutomationGraph(config: AutomationConfig): string[] {
	const issues: string[] = []
	const graph = config.graph
	if (!graph || !Array.isArray(graph.nodes) || !Array.isArray(graph.edges)) {
		return ["Automation graph is missing or malformed."]
	}

	const nodeIds = new Set<string>()
	const nodeById = new Map<string, GraphNode>()
	for (const node of graph.nodes) {
		if (!node || typeof node.id !== "string" || !node.id.trim()) {
			issues.push("A graph node is missing an id.")
			continue
		}
		if (nodeIds.has(node.id)) issues.push(`Duplicate node id: ${node.id}`)
		nodeIds.add(node.id)
		nodeById.set(node.id, node)
		if (!VALID_NODE_TYPES.has(String(node.type))) issues.push(`Unsupported node type on ${node.id}: ${String(node.type)}`)
	}

	if (graph.entryNodeId && !nodeIds.has(graph.entryNodeId)) issues.push(`Entry node does not exist: ${graph.entryNodeId}`)

	for (const edge of graph.edges) {
		if (!edge || typeof edge.id !== "string" || !edge.id.trim()) issues.push("A graph edge is missing an id.")
		if (!nodeIds.has(edge?.from)) issues.push(`Edge ${edge?.id || "(missing id)"} starts at missing node: ${edge?.from || "(empty)"}`)
		if (!nodeIds.has(edge?.to)) issues.push(`Edge ${edge?.id || "(missing id)"} ends at missing node: ${edge?.to || "(empty)"}`)
		if (isConversionGraphNode(nodeById.get(edge?.from)) || isConversionGraphNode(nodeById.get(edge?.to))) {
			issues.push(`Edge ${edge?.id || "(missing id)"} uses a data-only conversion node.`)
		}
	}

	const variableNodeIds = new Set<string>()
	for (const variable of config.variableNodes ?? []) {
		if (!variable?.id) issues.push("A variable node is missing an id.")
		if (!VALID_VARIABLE_TYPES.has(String(variable?.type))) issues.push(`Variable ${variable?.name || variable?.id || "(unnamed)"} has an unsupported type.`)
		if (variable?.id && VALID_VARIABLE_TYPES.has(String(variable.type))) variableNodeIds.add(variable.id)
	}

	const dataWireSourceIds = new Set(nodeIds)
	for (const variableId of variableNodeIds) dataWireSourceIds.add(variableId)
	dataWireSourceIds.add("trigger")
	for (const wire of config.dataWires ?? []) {
		if (!wire || typeof wire.id !== "string" || !wire.id.trim()) issues.push("A data wire is missing an id.")
		if (!dataWireSourceIds.has(wire?.fromNode)) issues.push(`Data wire ${wire?.id || "(missing id)"} starts at missing node: ${wire?.fromNode || "(empty)"}`)
		if (!nodeIds.has(wire?.toNode)) issues.push(`Data wire ${wire?.id || "(missing id)"} ends at missing node: ${wire?.toNode || "(empty)"}`)
		if (!wire?.fromPort || !wire?.toPort) issues.push(`Data wire ${wire?.id || "(missing id)"} is missing a port.`)
	}

	for (const subgraph of config.subgraphs ?? []) {
		if (!subgraph?.id || !Array.isArray(subgraph.nodes) || !Array.isArray(subgraph.edges)) {
			issues.push(`Subgraph ${subgraph?.name || subgraph?.id || "(unnamed)"} is malformed.`)
		}
	}

	return issues
}

export function repairAutomation(config: AutomationConfig): AutomationConfig {
	const repaired = cloneAutomationConfig(config)
	repaired.name ||= ""
	repaired.graph = repairGraphModel(repaired.graph)
	repaired.subgraphs = Array.isArray(repaired.subgraphs) ? repaired.subgraphs.map(repairSubgraph).filter(Boolean) as SubgraphDefinition[] : []
	repaired.variableNodes = repairVariableNodes(repaired.variableNodes)
	const mainWireSourceIds = new Set(repaired.graph.nodes.map((node) => node.id))
	for (const variable of repaired.variableNodes) mainWireSourceIds.add(variable.id)
	mainWireSourceIds.add("trigger")
	const mainWireTargetIds = new Set(repaired.graph.nodes.map((node) => node.id))
	repaired.dataWires = repairDataWires(repaired.dataWires, mainWireSourceIds, mainWireTargetIds)
	return repaired
}

export function cloneAutomationConfig(config: AutomationConfig): AutomationConfig {
	return JSON.parse(JSON.stringify(config)) as AutomationConfig
}

function repairGraphModel(graph: AutomationGraph | undefined): AutomationGraph {
	if (!graph || !Array.isArray(graph.nodes) || !Array.isArray(graph.edges)) return { nodes: [], edges: [], entryNodeId: "" }
	const nodes = dedupeNodes(graph.nodes)
	const nodeIds = new Set(nodes.map((node) => node.id))
	const edges = graph.edges
		.filter((edge) =>
			edge?.id &&
			nodeIds.has(edge.from) &&
			nodeIds.has(edge.to) &&
			!isConversionGraphNode(nodes.find((node) => node.id === edge.from)) &&
			!isConversionGraphNode(nodes.find((node) => node.id === edge.to))
		)
		.map((edge) => ({ id: String(edge.id), from: edge.from, to: edge.to, port: edge.port }))
	return {
		nodes,
		edges,
		entryNodeId: graph.entryNodeId && nodeIds.has(graph.entryNodeId) ? graph.entryNodeId : nodes[0]?.id ?? "",
	}
}

function repairSubgraph(subgraph: SubgraphDefinition): SubgraphDefinition | undefined {
	if (!subgraph?.id || !Array.isArray(subgraph.nodes) || !Array.isArray(subgraph.edges)) return undefined
	const repaired = repairGraphModel(subgraph)
	const wireNodeIds = new Set(repaired.nodes.map((node) => node.id))
	for (const param of subgraph.parameters ?? []) {
		if (param?.name) wireNodeIds.add(`__param:${param.name}`)
	}
	for (const output of subgraph.outputs ?? []) {
		if (output?.name) wireNodeIds.add(`__output:${output.name}`)
	}
	return {
		...subgraph,
		nodes: repaired.nodes,
		edges: repaired.edges,
		dataWires: repairDataWires(subgraph.dataWires, wireNodeIds),
		entryNodeId: repaired.entryNodeId,
		parameters: Array.isArray(subgraph.parameters) ? subgraph.parameters : [],
		outputs: Array.isArray(subgraph.outputs) ? subgraph.outputs : [],
	}
}

function dedupeNodes(nodes: GraphNode[]): GraphNode[] {
	const seen = new Set<string>()
	return nodes
		.filter((node) => node?.id && !seen.has(node.id) && VALID_NODE_TYPES.has(String(node.type)))
		.map((node) => {
			seen.add(node.id)
			return {
				...node,
				x: Number.isFinite(Number(node.x)) ? Number(node.x) : 0,
				y: Number.isFinite(Number(node.y)) ? Number(node.y) : 0,
			} as GraphNode
		})
}

function repairDataWires(wires: AutomationDataWire[] | undefined, sourceIds: Set<string>, targetIds = sourceIds): AutomationDataWire[] {
	if (!Array.isArray(wires)) return []
	return wires.filter((wire) => wire?.id && sourceIds.has(wire.fromNode) && targetIds.has(wire.toNode) && wire.fromPort && wire.toPort)
}

function repairVariableNodes(nodes: AutomationVariableNode[] | undefined): AutomationVariableNode[] {
	if (!Array.isArray(nodes)) return []
	return nodes.filter((node) => node?.id && VALID_VARIABLE_TYPES.has(String(node.type)))
}

function isConversionGraphNode(node: GraphNode | undefined) {
	return node?.type === "action" && isCoreConversionAction(node.plugin, node.action)
}
