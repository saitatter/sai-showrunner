import { describe, expect, it } from "vitest"
import type { AutomationGraph } from "showrunner-schema"
import { buildGraphFromAutomationGraph } from "./useNodeRendering"

function pluginMap() {
	return new Map([
		[
			"obs",
			{
				name: "OBS",
				actions: {
					scene: { name: "Switch Scene", icon: "mdi mdi-monitor", type: "regular" },
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
})
