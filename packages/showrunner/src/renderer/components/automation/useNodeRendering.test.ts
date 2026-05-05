import { describe, expect, it } from "vitest"
import type { AutomationConfig, AutomationGraph } from "showrunner-schema"
import { buildGraph, buildGraphFromAutomationGraph } from "./useNodeRendering"

function pluginMap() {
	return new Map([
		[
			"obs",
			{
				name: "OBS",
				actions: {
					scene: { name: "Switch Scene", icon: "mdi mdi-monitor", type: "regular" },
				},
				triggers: {
					streamStart: {
						name: "Stream Started",
						context: {
							type: Object,
							properties: {
								viewerName: { type: String },
							},
						},
					},
				},
			},
		],
	])
}

describe("useNodeRendering", () => {
	it("renders existing action nodes even when plugin visibility hides them from creation menus", () => {
		const graph: AutomationGraph = {
			entryNodeId: "node-1",
			nodes: [
				{
					id: "node-1",
					type: "action",
					plugin: "obs",
					action: "scene",
					config: {},
					x: 10,
					y: 20,
				},
			],
			edges: [],
		}

		const rendered = buildGraphFromAutomationGraph(graph, pluginMap())

		expect(rendered.nodes[0]).toMatchObject({
			id: "node-1",
			title: "Switch Scene",
			subtitle: "OBS / scene",
		})
		expect(rendered.nodes[0].missing).toBeUndefined()
	})

	it("renders explicit trigger nodes before graph nodes", () => {
		const automation: AutomationConfig = {
			name: "Graph v2",
			schemaVersion: 2,
			triggerNodes: [
				{
					id: "trigger:stream-start",
					plugin: "obs",
					trigger: "streamStart",
					config: {},
					x: 120,
					y: 140,
				},
			],
			graph: {
				entryNodeId: "node-1",
				nodes: [
					{
						id: "node-1",
						type: "action",
						plugin: "obs",
						action: "scene",
						config: {},
						x: 420,
						y: 140,
					},
				],
				edges: [],
			},
			subgraphs: [],
			dataWires: [],
			variableNodes: [],
		}

		const rendered = buildGraph(automation, pluginMap(), () => undefined)

		expect(rendered.nodes[0]).toMatchObject({
			id: "trigger:stream-start",
			kind: "trigger",
			title: "Stream Start",
			subtitle: "obs / streamStart",
			x: 120,
			y: 140,
		})
		expect(rendered.nodes[0].outputPorts?.map((port) => port.key)).toEqual(["viewerName"])
		expect(rendered.edges).toContainEqual({
			id: "trigger:stream-start:node-1",
			from: "trigger:stream-start",
			to: "node-1",
		})
	})
})
