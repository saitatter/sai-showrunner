import type { EdgeData, NodeData } from "./useNodeRendering"

export interface InvalidFlowEdgeIssue {
	id: string
	from: string
	to: string
	message: string
}

export function getInvalidFlowEdgeIssues(edges: Pick<EdgeData, "id" | "from" | "to">[], nodes: Pick<NodeData, "id" | "kind" | "title">[]): InvalidFlowEdgeIssue[] {
	const nodeById = new Map(nodes.map((node) => [node.id, node]))
	const issues: InvalidFlowEdgeIssue[] = []

	for (const edge of edges) {
		const fromNode = nodeById.get(edge.from)
		const toNode = nodeById.get(edge.to)
		if (!fromNode) {
			issues.push({ id: edge.id, from: edge.from, to: edge.to, message: `Sequence edge starts at missing node: ${edge.from}` })
			continue
		}
		if (!toNode) {
			issues.push({ id: edge.id, from: edge.from, to: edge.to, message: `Sequence edge ends at missing node: ${edge.to}` })
			continue
		}
		if (fromNode.kind === "conversion" || toNode.kind === "conversion") {
			issues.push({
				id: edge.id,
				from: edge.from,
				to: edge.to,
				message: `Conversion nodes are data-only: ${fromNode.title} -> ${toNode.title}`,
			})
			continue
		}
		if (fromNode.kind === "return" || fromNode.kind === "break" || fromNode.kind === "continue") {
			issues.push({
				id: edge.id,
				from: edge.from,
				to: edge.to,
				message: `${fromNode.title} is terminal and cannot continue sequence flow.`,
			})
		}
	}

	return issues
}
