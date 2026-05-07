import { computed, ref } from "vue"
import { describe, expect, it } from "vitest"
import type { AutomationConfig, AutomationDataWire } from "showrunner-schema"
import { useSubgraphCollapse } from "./useSubgraphCollapse"
import type { NodeData } from "./useNodeRendering"

describe("useSubgraphCollapse", () => {
	it("uses supported port expressions for generated subgraph outputs", () => {
		const model = ref<AutomationConfig>({
			name: "test",
			schemaVersion: 2,
			graph: {
				nodes: [
					{ id: "producer", type: "action", plugin: "p", action: "producer", config: {}, x: 0, y: 0 },
					{ id: "echo", type: "action", plugin: "p", action: "echo", config: {}, x: 220, y: 0 },
					{ id: "consumer", type: "action", plugin: "p", action: "consumer", config: {}, x: 440, y: 0 },
				],
				edges: [
					{ id: "producer-echo", from: "producer", to: "echo" },
					{ id: "echo-consumer", from: "echo", to: "consumer" },
				],
				entryNodeId: "producer",
			},
			subgraphs: [],
			dataWires: [
				{ id: "in", fromNode: "producer", fromPort: "value", toNode: "echo", toPort: "text" },
				{ id: "out", fromNode: "echo", fromPort: "echoed", toNode: "consumer", toPort: "message" },
			],
			variableNodes: [],
		})
		const dataWires = computed({
			get: () => model.value.dataWires as AutomationDataWire[],
			set: (value) => {
				model.value.dataWires = value
			},
		})
		const nodes = computed<NodeData[]>(() => [
			{ id: "producer", kind: "action", title: "Producer", subtitle: "", icon: "", x: 0, y: 0, height: 80, outputPorts: [{ key: "value", label: "Value", type: "string" }] },
			{ id: "echo", kind: "action", title: "Echo", subtitle: "", icon: "", x: 220, y: 0, height: 80, inputPorts: [{ key: "text", label: "Text", type: "string" }], outputPorts: [{ key: "echoed", label: "Echoed", type: "string" }] },
			{ id: "consumer", kind: "action", title: "Consumer", subtitle: "", icon: "", x: 440, y: 0, height: 80, inputPorts: [{ key: "message", label: "Message", type: "string" }] },
		])
		const selectedNodeIds = ref(new Set(["echo"]))
		const focusedSubgraphId = ref<string>()
		const subgraphsOpen = ref(false)
		const collapse = useSubgraphCollapse({
			model,
			activeGraph: computed(() => model.value.graph),
			selectedNodeIds,
			dataWires,
			nodes,
			focusedSubgraphId,
			subgraphsOpen,
			focusNode: () => undefined,
			commitUndo: () => undefined,
		})

		collapse.collapseSelectionToSubgraph()

		expect(model.value.subgraphs).toHaveLength(1)
		expect(model.value.subgraphs[0].outputs).toEqual([
			{
				name: "echoed",
				type: "string",
				expression: { type: "port", nodeId: "echo", port: "echoed" },
			},
		])
		const callNode = model.value.graph.nodes.find((node) => node.type === "subgraphCall")
		expect(callNode).toBeTruthy()
		expect(model.value.dataWires.some((wire) => wire.fromNode === callNode?.id && wire.fromPort === "echoed")).toBe(true)
	})

	it("does not collapse selections with multiple outgoing sequence exits", () => {
		const model = ref<AutomationConfig>({
			name: "test",
			schemaVersion: 2,
			graph: {
				nodes: [
					{ id: "branch", type: "if", config: { condition: { type: "literal", value: true } }, x: 0, y: 0 },
					{ id: "true-target", type: "action", plugin: "p", action: "trueTarget", config: {}, x: 220, y: -80 },
					{ id: "false-target", type: "action", plugin: "p", action: "falseTarget", config: {}, x: 220, y: 80 },
				],
				edges: [
					{ id: "branch-true", from: "branch", to: "true-target", port: "true" },
					{ id: "branch-false", from: "branch", to: "false-target", port: "false" },
				],
				entryNodeId: "branch",
			},
			subgraphs: [],
			dataWires: [],
			variableNodes: [],
		})
		const dataWires = computed({
			get: () => model.value.dataWires as AutomationDataWire[],
			set: (value) => {
				model.value.dataWires = value
			},
		})
		const selectedNodeIds = ref(new Set(["branch"]))
		let undoCommitted = false
		const collapse = useSubgraphCollapse({
			model,
			activeGraph: computed(() => model.value.graph),
			selectedNodeIds,
			dataWires,
			nodes: computed(() => []),
			focusedSubgraphId: ref(),
			subgraphsOpen: ref(false),
			focusNode: () => undefined,
			commitUndo: () => {
				undoCommitted = true
			},
		})

		expect(collapse.collapseSelectionToSubgraph()).toBe(false)
		expect(model.value.subgraphs).toHaveLength(0)
		expect(model.value.graph.nodes.some((node) => node.id === "branch")).toBe(true)
		expect(model.value.graph.edges).toHaveLength(2)
		expect(undoCommitted).toBe(false)
	})
})
