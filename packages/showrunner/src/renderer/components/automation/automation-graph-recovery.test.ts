import { describe, expect, it } from "vitest"
import type { AutomationConfig } from "showrunner-schema"
import { repairAutomation, validateAutomationGraph } from "./automation-graph-recovery"

describe("automation graph recovery", () => {
	it("accepts newly created unnamed variable nodes", () => {
		const config: AutomationConfig = {
			name: "test",
			schemaVersion: 2,
			graph: {
				nodes: [],
				edges: [],
				entryNodeId: "",
			},
			subgraphs: [],
			dataWires: [],
			variableNodes: [
				{
					id: "zbliBWurDMZzLqQUaynNz",
					name: "",
					type: "string",
					value: "",
					x: 630,
					y: 378,
				},
			],
		}

		expect(validateAutomationGraph(config)).toEqual([])
		expect(repairAutomation(config).variableNodes).toEqual(config.variableNodes)
	})

	it("still rejects variable nodes without ids", () => {
		const config: AutomationConfig = {
			name: "broken",
			schemaVersion: 2,
			graph: { nodes: [], edges: [], entryNodeId: "" },
			subgraphs: [],
			dataWires: [],
			variableNodes: [
				{
					id: "",
					name: "",
					type: "number",
					value: 0,
					x: 0,
					y: 0,
				},
			],
		}

		expect(validateAutomationGraph(config)).toContain("A variable node is missing an id.")
		expect(repairAutomation(config).variableNodes).toEqual([])
	})

	it("accepts data wires that start at variable nodes", () => {
		const config: AutomationConfig = {
			name: "test",
			schemaVersion: 2,
			graph: {
				nodes: [
					{
						id: "4DBSUs3TbcaKCrzSA8_Qc",
						type: "action",
						plugin: "youtube",
						action: "sendChatMessage",
						config: { message: "" },
						x: 546,
						y: 252,
					},
				],
				edges: [],
				entryNodeId: "4DBSUs3TbcaKCrzSA8_Qc",
			},
			subgraphs: [],
			dataWires: [
				{
					id: "0eoWoMCPJuH85FVsE_PaO:value->4DBSUs3TbcaKCrzSA8_Qc:message",
					fromNode: "0eoWoMCPJuH85FVsE_PaO",
					fromPort: "value",
					toNode: "4DBSUs3TbcaKCrzSA8_Qc",
					toPort: "message",
				},
			],
			variableNodes: [
				{
					id: "0eoWoMCPJuH85FVsE_PaO",
					name: "",
					type: "string",
					value: "",
					x: 252,
					y: 210,
				},
			],
		}

		expect(validateAutomationGraph(config)).toEqual([])
		expect(repairAutomation(config).dataWires).toEqual(config.dataWires)
	})

	it("rejects and repairs sequence edges attached to conversion nodes", () => {
		const config: AutomationConfig = {
			name: "conversion-flow",
			schemaVersion: 2,
			graph: {
				nodes: [
					{
						id: "convert-1",
						type: "action",
						plugin: "ShowRunner",
						action: "convertStringToNumber",
						config: { value: "", fallback: 0 },
						x: 100,
						y: 100,
					},
					{
						id: "action-1",
						type: "action",
						plugin: "youtube",
						action: "sendChatMessage",
						config: { message: "" },
						x: 360,
						y: 100,
					},
				],
				edges: [{ id: "convert-1:action-1", from: "convert-1", to: "action-1" }],
				entryNodeId: "action-1",
			},
			subgraphs: [],
			dataWires: [],
			variableNodes: [],
		}

		expect(validateAutomationGraph(config)).toContain("Edge convert-1:action-1 uses a data-only conversion node.")
		expect(repairAutomation(config).graph.edges).toEqual([])
	})
})
