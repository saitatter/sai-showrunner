import { nanoid } from "nanoid"
import type { AutomationGraph, GraphNodeType } from "showrunner-schema"
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
