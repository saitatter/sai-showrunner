import { describe, expect, it } from "vitest"
import { normalizeAutomationConfig } from "./automation-migration"

describe("automation migration", () => {
	it("normalizes old automation data so graph-only editor can open it", () => {
		const legacy = {
			name: "Legacy automation",
			sequence: { actions: [] },
			floatingSequences: [{ id: "old-floating" }],
			graph: {
				nodes: [{ id: "a", type: "action", plugin: "test", action: "run", config: {}, x: 10, y: 20 }],
				edges: [{ id: "a:b", from: "a", to: "b" }],
				entryNodeId: "a",
			},
			subgraphs: [
				{
					id: "sub",
					name: "Sub",
					nodes: [{ id: "s", type: "return", x: 0, y: 0 }],
					edges: [],
					entryNodeId: "s",
				},
			],
			dataWires: [{ id: "wire", fromNode: "trigger", fromPort: "value", toNode: "a", toPort: "input" }],
			plugin: "twitch",
			trigger: "chatMessage",
			config: { command: "!test" },
		}

		const normalized = normalizeAutomationConfig(legacy)

		expect(normalized.schemaVersion).toBe(2)
		expect(normalized.graph.entryNodeId).toBe("a")
		expect(normalized.subgraphs[0]).toMatchObject({ parameters: [], outputs: [], dataWires: [] })
		expect(normalized.variableNodes).toEqual([])
		expect(normalized.triggerNodes).toEqual([
			{
				id: "trigger",
				plugin: "twitch",
				trigger: "chatMessage",
				config: { command: "!test" },
				stop: undefined,
				x: 42,
				y: 88,
			},
		])
		expect("sequence" in normalized).toBe(false)
		expect("floatingSequences" in normalized).toBe(false)
	})

	it("creates an empty graph shell for malformed legacy data", () => {
		const normalized = normalizeAutomationConfig({
			name: "Malformed legacy automation",
			sequence: { actions: [] },
			graph: null,
			subgraphs: "bad",
			dataWires: "bad",
			variableNodes: "bad",
		})

		expect(normalized).toMatchObject({
			name: "Malformed legacy automation",
			schemaVersion: 2,
			graph: { nodes: [], edges: [], entryNodeId: "" },
			subgraphs: [],
			dataWires: [],
			variableNodes: [],
			triggerNodes: [],
		})
	})

	it("keeps existing explicit trigger nodes and normalizes missing coordinates", () => {
		const normalized = normalizeAutomationConfig({
			name: "Graph v2 automation",
			graph: { nodes: [], edges: [], entryNodeId: "" },
			triggerNodes: [
				{ id: "trigger:one", plugin: "twitch", trigger: "chatMessage", config: { channel: "main" } },
				{ id: "", plugin: "bad", trigger: "bad", config: {} },
			],
		})

		expect(normalized.triggerNodes).toEqual([
			{
				id: "trigger:one",
				plugin: "twitch",
				trigger: "chatMessage",
				config: { channel: "main" },
				stop: undefined,
				x: 42,
				y: 88,
			},
		])
	})
})
