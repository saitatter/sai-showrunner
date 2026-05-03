import { describe, expect, it } from "vitest"
import type { AutomationGraph, GraphNodeType } from "showrunner-schema"
import { connectFlowToNode, isTerminalControlFlowNode, resolveContextActionPosition } from "./automation-graph-editing"

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

	it("places context-menu actions at the canvas click position", () => {
		expect(resolveContextActionPosition(null, { canvasPoint: { x: 320, y: 180 } })).toEqual({ x: 320, y: 180 })
	})

	it("keeps node context-menu actions at the click position instead of falling back to zero", () => {
		expect(resolveContextActionPosition(null, { nodeId: "node-1", canvasPoint: { x: 420, y: 260 } })).toEqual({
			x: 420,
			y: 260,
		})
	})

	it("uses pending flow positions before generic context-menu positions", () => {
		expect(
			resolveContextActionPosition(
				{ fromNode: "start", canvasPoint: { x: 640, y: 320 } },
				{ nodeId: "node-1", canvasPoint: { x: 420, y: 260 } }
			)
		).toEqual({ x: 640, y: 320 })
	})
})
