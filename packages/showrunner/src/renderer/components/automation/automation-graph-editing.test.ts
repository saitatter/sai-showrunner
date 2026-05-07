import { describe, expect, it } from "vitest"
import type { AutomationGraph, GraphNodeType } from "showrunner-schema"
import { addGraphActionNode, connectFlowToNode, insertActionInGraph, insertActionOnGraphEdge, isTerminalControlFlowNode, resolveContextActionPosition } from "./automation-graph-editing"

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

	it("keeps conversion nodes out of sequence flow when inserted after another node", () => {
		const graph = makeGraph()

		insertActionInGraph(
			graph,
			{
				id: "convert-1",
				plugin: "ShowRunner",
				action: "convertStringToNumber",
				config: { value: "", fallback: 0 },
			},
			{
				afterNodeId: "start",
				position: { x: 120, y: 88 },
				anchorNodes: [{ id: "start", x: 0, y: 0 }],
				snapCoordinate: (value) => value,
				anchorOffsetX: 285,
			}
		)

		expect(graph.edges).toEqual([{ id: "start:next", from: "start", to: "next" }])
	})

	it("does not make conversion nodes the graph entry", () => {
		const graph: AutomationGraph = { entryNodeId: "", nodes: [], edges: [] }

		addGraphActionNode(graph, {
			id: "convert-1",
			plugin: "ShowRunner",
			action: "convertJsonStringToObject",
			config: { value: "{}" },
		}, { x: 10, y: 20 })

		expect(graph.entryNodeId).toBe("")
	})

	it("does not split sequence edges with conversion nodes", () => {
		const graph = makeGraph()

		insertActionOnGraphEdge(
			graph,
			{
				id: "convert-1",
				plugin: "ShowRunner",
				action: "convertStringToBoolean",
				config: { value: "", fallback: false },
			},
			{ id: "start:next", from: "start", to: "next" },
			{ x: 120, y: 88 }
		)

		expect(graph.edges).toEqual([{ id: "start:next", from: "start", to: "next" }])
	})

	it("places context-menu actions at the canvas click position", () => {
		expect(resolveContextActionPosition(null, { canvasPoint: { x: 320, y: 180 } })).toEqual({ x: 320, y: 180 })
	})

	it("places node context-menu actions to the right of the anchor node", () => {
		expect(
			resolveContextActionPosition(
				null,
				{ nodeId: "node-1", canvasPoint: { x: 420, y: 260 } },
				{ x: 120, y: 180 },
				285
			)
		).toEqual({ x: 405, y: 180 })
	})

	it("keeps node context-menu actions at the click position when the anchor node is unavailable", () => {
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
