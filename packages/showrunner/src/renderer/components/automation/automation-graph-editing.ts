import { nanoid } from "nanoid"
import type { AutomationGraph, GraphNodeType } from "showrunner-schema"

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
