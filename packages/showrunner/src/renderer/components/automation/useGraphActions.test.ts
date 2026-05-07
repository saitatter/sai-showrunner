import { computed, ref } from "vue"
import { describe, expect, it, vi } from "vitest"
import type { AutomationConfig } from "showrunner-schema"
import { useGraphActions } from "./useGraphActions"
import type { NodeData } from "./useNodeRendering"

function createGraphActionsHarness() {
	const model = ref<AutomationConfig>({
		name: "test",
		schemaVersion: 2,
		graph: {
			nodes: [{ id: "action-1", type: "action", plugin: "p", action: "a", config: {}, x: 100, y: 100 }],
			edges: [],
			entryNodeId: "action-1",
		},
		triggerNodes: [{ id: "trigger-1", plugin: "twitch", trigger: "chat", config: {}, x: 10, y: 10 }],
		subgraphs: [],
		dataWires: [{ id: "wire", fromNode: "trigger-1", fromPort: "value", toNode: "action-1", toPort: "message" }],
		variableNodes: [],
	})
	const selectedNodeId = ref("trigger-1")
	const selectedNodeIds = ref(new Set(["trigger-1"]))
	const selectedNode = computed<NodeData | undefined>(() => ({
		id: "trigger-1",
		kind: "trigger",
		title: "Trigger",
		subtitle: "",
		icon: "",
		x: 10,
		y: 10,
		height: 80,
	}))
	const commitUndo = vi.fn()
	const clearSelection = vi.fn(() => {
		selectedNodeId.value = undefined
		selectedNodeIds.value = new Set()
	})
	const dataWires = computed({
		get: () => model.value.dataWires,
		set: (value) => {
			model.value.dataWires = value
		},
	})
	const variableNodes = computed({
		get: () => model.value.variableNodes,
		set: (value) => {
			model.value.variableNodes = value
		},
	})

	const actions = useGraphActions({
		model,
		activeGraph: computed(() => model.value.graph),
		selectedActionInfo: computed(() => undefined),
		selectedNode,
		selectedNodeId,
		selectedNodeIds,
		selectedActionToAdd: ref(""),
		contextMenu: ref({}),
		pendingFlowConnection: ref(null),
		nodes: computed(() => [selectedNode.value!]),
		nodePositions: computed(() => ({})),
		variableNodes,
		dataWires,
		dropTargetNodeId: ref(),
		dropTargetEdgeId: ref(),
		ghostNode: ref(null),
		configOpen: ref(false),
		pluginStore: {
			pluginMap: new Map(),
			createAction: vi.fn(),
			getAction: vi.fn(),
		},
		anchorOffsetX: 220,
		ensureGraph: () => model.value.graph,
		snapCoordinate: (value) => value,
		getCanvasPoint: () => ({ x: 0, y: 0 }),
		focusNode: vi.fn(),
		clearSelection,
		closeContextMenu: vi.fn(),
		trackRecentlyUsed: vi.fn(),
		commitUndo,
	})

	return { actions, model, commitUndo, clearSelection }
}

describe("useGraphActions", () => {
	it("deletes selected explicit trigger nodes from triggerNodes and data wires", () => {
		const { actions, model, commitUndo, clearSelection } = createGraphActionsHarness()

		actions.deleteSelectedAction()

		expect(model.value.triggerNodes).toEqual([])
		expect(model.value.dataWires).toEqual([])
		expect(model.value.graph.nodes.map((node) => node.id)).toEqual(["action-1"])
		expect(clearSelection).toHaveBeenCalled()
		expect(commitUndo).toHaveBeenCalled()
	})
})
