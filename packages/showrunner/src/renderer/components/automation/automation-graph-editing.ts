import { nanoid } from "nanoid"
import type { ActionInfo } from "showrunner-ui-core"
import type { AutomationGraph, GraphNode, GraphNodeType } from "showrunner-schema"
import type { NodePosition } from "./useNodeCanvas"

export interface PendingFlowConnection {
	fromNode: string
	fromPort?: string
	canvasPoint: NodePosition
}

export interface ContextMenuPlacement {
	nodeId?: string
	canvasPoint?: NodePosition
}

export interface ContextMenuAnchorNode {
	x: number
	y: number
}

export interface FlowEdgeLike {
	id: string
	from: string
	to: string
	port?: string
}

export interface FlowAnchorNode {
	id: string
	x: number
	y: number
}

export function toGraphActionNode(action: ActionInfo, position: NodePosition): Extract<GraphNode, { type: "action" }> {
	return {
		id: action.id,
		type: "action",
		plugin: action.plugin,
		action: action.action,
		config: structuredClone(action.config ?? {}),
		resultMapping: action.resultMapping ? structuredClone(action.resultMapping) : undefined,
		x: position.x,
		y: position.y,
	}
}

export function addGraphActionNode(graph: AutomationGraph, action: ActionInfo, position: NodePosition) {
	const node = toGraphActionNode(action, position)
	graph.nodes.push(node)
	if (!graph.entryNodeId) graph.entryNodeId = node.id
	return node
}

export function connectFlowToNode(
	graph: AutomationGraph,
	fromNode: string,
	fromPort: string | undefined,
	toNode: string,
	isTerminal = false
) {
	const outgoing = graph.edges.find((edge) => edge.from === fromNode && (edge.port ?? undefined) === fromPort)
	if (outgoing) {
		const previousTo = outgoing.to
		outgoing.to = toNode
		if (!isTerminal && previousTo && previousTo !== toNode) {
			graph.edges.push({ id: nanoid(), from: toNode, to: previousTo })
		}
		return
	}
	graph.edges.push({ id: nanoid(), from: fromNode, to: toNode, port: fromPort })
}

export function insertActionInGraph(
	graph: AutomationGraph,
	action: ActionInfo,
	options: {
		afterNodeId?: string
		afterPort?: string
		position?: NodePosition
		anchorNodes: FlowAnchorNode[]
		snapCoordinate: (value: number) => number
		anchorOffsetX: number
	}
) {
	const canAnchorFlow = options.afterNodeId === "trigger" || Boolean(options.afterNodeId && graph.nodes.some((node) => node.id === options.afterNodeId))
	const flowAnchorId = canAnchorFlow ? options.afterNodeId : undefined
	const anchor = flowAnchorId && flowAnchorId !== "trigger" ? options.anchorNodes.find((node) => node.id === flowAnchorId) : undefined
	const fallbackPosition = options.position ?? {
		x: options.snapCoordinate((anchor?.x ?? 42) + options.anchorOffsetX),
		y: options.snapCoordinate(anchor?.y ?? 88),
	}
	const node = addGraphActionNode(graph, action, fallbackPosition)

	if (!flowAnchorId) return node

	if (flowAnchorId === "trigger") {
		const previousEntry = graph.entryNodeId && graph.entryNodeId !== node.id ? graph.entryNodeId : ""
		graph.entryNodeId = node.id
		if (previousEntry) {
			graph.edges.push({ id: `${node.id}:${previousEntry}`, from: node.id, to: previousEntry })
		}
		return node
	}

	connectFlowToNode(graph, flowAnchorId, options.afterPort, node.id)
	return node
}

export function insertActionOnGraphEdge(graph: AutomationGraph, action: ActionInfo, edge: FlowEdgeLike, position: NodePosition) {
	const node = addGraphActionNode(graph, action, position)

	if (edge.from === "trigger") {
		const previousEntry = graph.entryNodeId && graph.entryNodeId !== node.id ? graph.entryNodeId : edge.to
		graph.entryNodeId = node.id
		if (previousEntry && previousEntry !== node.id) {
			graph.edges.push({ id: `${node.id}:${previousEntry}`, from: node.id, to: previousEntry })
		}
		return node
	}

	const existing = graph.edges.find((graphEdge) => graphEdge.id === edge.id)
	if (existing) {
		const previousTo = existing.to
		existing.to = node.id
		graph.edges.push({ id: `${node.id}:${previousTo}`, from: node.id, to: previousTo })
	} else {
		graph.edges.push({ id: `${edge.from}:${node.id}`, from: edge.from, to: node.id, port: edge.port })
		graph.edges.push({ id: `${node.id}:${edge.to}`, from: node.id, to: edge.to })
	}
	return node
}

export function isTerminalControlFlowNode(type: GraphNodeType) {
	return type === "break" || type === "continue" || type === "return"
}

export function resolveContextActionPosition(
	pendingFlow: PendingFlowConnection | null | undefined,
	contextMenu: ContextMenuPlacement,
	anchorNode?: ContextMenuAnchorNode,
	anchorOffsetX = 0
) {
	if (pendingFlow?.canvasPoint) return pendingFlow.canvasPoint
	if (contextMenu.nodeId && anchorNode) {
		return { x: anchorNode.x + anchorOffsetX, y: anchorNode.y }
	}
	return contextMenu.canvasPoint
}
