import { describe, expect, it } from "vitest"
import type { AutomationGraph, GraphNodeType } from "showrunner-schema"
import { connectFlowToNode, isTerminalControlFlowNode } from "./automation-graph-editing"

function makeGraph(): AutomationGraph {
	return {
		entryNodeId: "start",
		nodes: [],
		edges: [{ id: "start:next", from: "start", to: "next" }],
	}
}

describe("automation graph editing", () => {
	it.each(["return", "break", "continue"] satisfies GraphNodeType[])(
		"does not reconnect downstream flow when inserting terminal %s nodes",
		(type) => {
			const graph = makeGraph()

			connectFlowToNode(graph, "start", undefined, type, isTerminalControlFlowNode(type))

			expect(graph.edges).toEqual([{ id: "start:next", from: "start", to: type }])
		}
	)

	it("reconnects downstream flow when inserting non-terminal nodes", () => {
		const graph = makeGraph()

		connectFlowToNode(graph, "start", undefined, "action-1")

		expect(graph.edges).toHaveLength(2)
		expect(graph.edges[0]).toEqual({ id: "start:next", from: "start", to: "action-1" })
		expect(graph.edges[1]).toMatchObject({ from: "action-1", to: "next" })
	})
})
