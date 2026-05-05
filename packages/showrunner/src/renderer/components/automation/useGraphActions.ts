import { nanoid } from "nanoid"
import type { ComputedRef, Ref, WritableComputedRef } from "vue"
import { ActionSelection } from "showrunner-ui-core"
import { ActionInfo, constructDefault, type AutomationDataWire, type AutomationGraph, type GraphNode } from "showrunner-schema"
import {
	addGraphActionNode as addGraphActionNodeToGraph,
	insertActionInGraph,
	insertActionOnGraphEdge,
	resolveContextActionPosition,
} from "./automation-graph-editing"
import { resolveActionDefinition } from "./actionLookup"
import { isConversionActionId } from "./useNodeContextMenu"
import type { NodePosition } from "./useNodeCanvas"
import type { EdgeData, NodeData } from "./useNodeRendering"

interface PendingFlowConnection {
	fromNode: string
	fromPort?: string
	canvasPoint: NodePosition
}

interface ContextMenuState {
	nodeId?: string
	canvasPoint?: NodePosition
}

interface UseGraphActionsOptions {
	activeGraph: ComputedRef<AutomationGraph | undefined>
	selectedActionInfo: ComputedRef<Extract<GraphNode, { type: "action" }> | undefined>
	selectedNode: ComputedRef<NodeData | undefined>
	selectedNodeId: Ref<string | undefined>
	selectedNodeIds: Ref<Set<string>>
	selectedActionToAdd: Ref<string>
	contextMenu: Ref<ContextMenuState>
	pendingFlowConnection: Ref<PendingFlowConnection | null>
	nodes: ComputedRef<NodeData[]>
	nodePositions: ComputedRef<Record<string, NodePosition>>
	variableNodes: WritableComputedRef<{ id: string }[]>
	dataWires: WritableComputedRef<AutomationDataWire[]>
	dropTargetNodeId: Ref<string | undefined>
	dropTargetEdgeId: Ref<string | undefined>
	ghostNode: Ref<NodePosition | null>
	configOpen: Ref<boolean>
	pluginStore: any
	anchorOffsetX: number
	ensureGraph: () => AutomationGraph
	snapCoordinate: (value: number) => number
	getCanvasPoint: (event: DragEvent) => NodePosition
	focusNode: (nodeId: string) => void
	clearSelection: () => void
	closeContextMenu: () => void
	trackRecentlyUsed: (key: string, kind: "action" | "trigger", name: string, icon: string, color: string) => void
	commitUndo: () => void
}

export function useGraphActions(options: UseGraphActionsOptions) {
	const {
		activeGraph,
		selectedActionInfo,
		selectedNode,
		selectedNodeId,
		selectedNodeIds,
		selectedActionToAdd,
		contextMenu,
		pendingFlowConnection,
		nodes,
		nodePositions,
		variableNodes,
		dataWires,
		dropTargetNodeId,
		dropTargetEdgeId,
		ghostNode,
		configOpen,
		pluginStore,
		anchorOffsetX,
		ensureGraph,
		snapCoordinate,
		getCanvasPoint,
		focusNode,
		clearSelection,
		closeContextMenu,
		trackRecentlyUsed,
		commitUndo,
	} = options
	let dropInProgress = false

	async function addActionFromPalette() {
		if (dropInProgress) return
		dropInProgress = true
		try {
			const selection = parseActionSelection(selectedActionToAdd.value)
			if (!selection) return

			const action = await pluginStore.createAction(selection)
			if (!action) return

			insertAction(action)
			focusNode(action.id)
			configOpen.value = true
			commitUndo()
		} finally {
			dropInProgress = false
		}
	}

	async function selectActionFromContext(actionKey: string) {
		if (dropInProgress) return
		dropInProgress = true
		try {
			const selection = parseActionSelection(actionKey)
			if (!selection) return

			const action = await createContextAction(selection)
			if (!action) return

			const plugin = pluginStore.pluginMap.get(selection.plugin)
			const actionDef = resolveActionDefinition(pluginStore.pluginMap, selection.plugin, selection.action)
			trackRecentlyUsed(actionKey, "action", actionDef?.name ?? selection.action, actionDef?.icon ?? "mdi mdi-play", String(plugin?.color ?? "#e9aaff"))

			const pendingFlow = pendingFlowConnection.value
			const contextAnchorNode = contextMenu.value.nodeId ? nodes.value.find((node) => node.id === contextMenu.value.nodeId) : undefined
			const position = resolveContextActionPosition(pendingFlow, contextMenu.value, contextAnchorNode, anchorOffsetX)
			insertAction(action, pendingFlow?.fromNode ?? contextMenu.value.nodeId, position, pendingFlow?.fromPort)
			if (position) nodePositions.value[action.id] = position
			focusNode(action.id)
			configOpen.value = true
			closeContextMenu()
			commitUndo()
		} finally {
			dropInProgress = false
		}
	}

	function startActionPaletteDrag(event: DragEvent, actionKey: string) {
		event.dataTransfer?.setData("application/showrunner-action", actionKey)
		event.dataTransfer?.setData("text/plain", actionKey)
		if (event.dataTransfer) event.dataTransfer.effectAllowed = "copy"
	}

	async function dropActionOnCanvas(event: DragEvent) {
		if (dropInProgress) return
		dropInProgress = true
		try {
			const action = await createDraggedAction(event)
			if (!action) return

			const position = getCanvasPoint(event)
			addGraphActionNode(action, position)
			nodePositions.value[action.id] = position
			focusNode(action.id)
			configOpen.value = true
			dropTargetNodeId.value = undefined
			ghostNode.value = null
			commitUndo()
		} finally {
			dropInProgress = false
		}
	}

	async function dropActionOnNode(event: DragEvent, node: NodeData) {
		if (dropInProgress) return
		dropInProgress = true
		try {
			const action = await createDraggedAction(event)
			if (!action) return

			const position = {
				x: snapCoordinate(node.x + anchorOffsetX),
				y: snapCoordinate(node.y),
			}
			insertAction(action, node.id, position)
			nodePositions.value[action.id] = position
			focusNode(action.id)
			configOpen.value = true
			dropTargetNodeId.value = undefined
			commitUndo()
		} finally {
			dropInProgress = false
		}
	}

	async function dropActionOnEdge(event: DragEvent, edge: EdgeData) {
		if (dropInProgress) return
		dropInProgress = true
		try {
			const action = await createDraggedAction(event)
			if (!action) return

			const fromNode = nodes.value.find((node) => node.id === edge.from)
			const toNode = nodes.value.find((node) => node.id === edge.to)
			const position = {
				x: snapCoordinate(((fromNode?.x ?? 42) + (toNode?.x ?? 42)) / 2),
				y: snapCoordinate(((fromNode?.y ?? 88) + (toNode?.y ?? 88)) / 2),
			}
			insertActionOnEdge(action, edge, position)
			nodePositions.value[action.id] = position
			focusNode(action.id)
			configOpen.value = true
			dropTargetEdgeId.value = undefined
			commitUndo()
		} finally {
			dropInProgress = false
		}
	}

	function duplicateSelectedAction() {
		const actionInfo = selectedActionInfo.value
		if (!actionInfo) return

		const clonedAction: ActionInfo = {
			id: nanoid(),
			plugin: actionInfo.plugin,
			action: actionInfo.action,
			config: structuredClone(actionInfo.config ?? {}),
			resultMapping: actionInfo.resultMapping ? structuredClone(actionInfo.resultMapping) : undefined,
		}
		const sourceNode = selectedNode.value
		const position = {
			x: snapCoordinate((sourceNode?.x ?? actionInfo.x) + anchorOffsetX),
			y: snapCoordinate(sourceNode?.y ?? actionInfo.y),
		}
		insertAction(clonedAction, actionInfo.id, position)
		nodePositions.value[clonedAction.id] = position
		focusNode(clonedAction.id)
		configOpen.value = true
		commitUndo()
	}

	function deleteSelectedAction() {
		const idsToDelete = selectedNodeIds.value.size > 1
			? [...selectedNodeIds.value].filter((id) => id !== "trigger")
			: selectedActionInfo.value ? [selectedNodeId.value!] : []

		if (idsToDelete.length === 0) return

		const variableIds = idsToDelete.filter((id) => variableNodes.value.some((node) => node.id === id))
		if (variableIds.length) {
			variableNodes.value = variableNodes.value.filter((node) => !variableIds.includes(node.id))
			dataWires.value = dataWires.value.filter((wire) => !variableIds.includes(wire.fromNode) && !variableIds.includes(wire.toNode))
		}
		const graphIds = idsToDelete.filter((id) => !variableIds.includes(id))
		deleteGraphNodes(graphIds)
		if (variableIds.length && !graphIds.length) {
			clearSelection()
			commitUndo()
		}
	}

	function canMoveSelectedAction(direction: -1 | 1) {
		return Boolean(selectedActionInfo.value && direction)
	}

	function moveSelectedAction(direction: -1 | 1) {
		const nodeId = selectedActionInfo.value?.id
		if (!nodeId || !canMoveSelectedAction(direction)) return
		const node = activeGraph.value?.nodes.find((graphNode) => graphNode.id === nodeId)
		if (!node) return
		node.x = snapCoordinate(node.x + direction * anchorOffsetX)
		nodePositions.value[node.id] = { x: node.x, y: node.y }
		commitUndo()
	}

	function addGraphActionNode(action: ActionInfo, position: NodePosition) {
		return addGraphActionNodeToGraph(ensureGraph(), action, position)
	}

	function insertAction(action: ActionInfo, afterNodeId = selectedNodeId.value, position?: NodePosition, afterPort?: string) {
		return insertActionInGraph(ensureGraph(), action, {
			afterNodeId,
			afterPort,
			position,
			anchorNodes: nodes.value,
			snapCoordinate,
			anchorOffsetX,
		})
	}

	function insertActionOnEdge(action: ActionInfo, edge: EdgeData, position: NodePosition) {
		return insertActionOnGraphEdge(ensureGraph(), action, edge, position)
	}

	function deleteGraphNodes(ids: string[]) {
		const graph = activeGraph.value
		if (!graph) return
		const idSet = new Set(ids)
		graph.nodes = graph.nodes.filter((node) => !idSet.has(node.id))
		graph.edges = graph.edges.filter((edge) => !idSet.has(edge.from) && !idSet.has(edge.to))
		dataWires.value = dataWires.value.filter((wire) => !idSet.has(wire.fromNode) && !idSet.has(wire.toNode))
		if (graph.entryNodeId && idSet.has(graph.entryNodeId)) {
			graph.entryNodeId = graph.nodes[0]?.id ?? ""
		}
		clearSelection()
		commitUndo()
	}

	async function createDraggedAction(event: DragEvent) {
		const actionKey =
			event.dataTransfer?.getData("application/showrunner-action") || event.dataTransfer?.getData("text/plain")
		const selection = parseActionSelection(actionKey || "")
		if (!selection) return undefined
		return createContextAction(selection)
	}

	async function createContextAction(selection: ActionSelection) {
		const action = await pluginStore.createAction(selection)
		if (action) return action
		if (!isCoreConversionSelection(selection)) return undefined

		const actionDef = pluginStore.getAction(selection)
		if (!actionDef || actionDef.type !== "regular") return createFallbackCoreConversionAction(selection)

		const result: Record<string, any> = {
			id: nanoid(),
			plugin: selection.plugin,
			action: selection.action,
			config: await constructDefault(actionDef.config),
		}

		if (actionDef.result) {
			result.resultMapping = {}
			for (const prop of Object.keys(actionDef.result.properties)) {
				result.resultMapping[prop] = prop
			}
		}

		return result as ActionInfo
	}

	return {
		addActionFromPalette,
		selectActionFromContext,
		startActionPaletteDrag,
		dropActionOnCanvas,
		dropActionOnNode,
		dropActionOnEdge,
		duplicateSelectedAction,
		deleteSelectedAction,
		canMoveSelectedAction,
		moveSelectedAction,
		insertAction,
	}
}

function parseActionSelection(value: string): ActionSelection | undefined {
	const [plugin, action] = value.split(":")
	if (!plugin || !action) return undefined
	return { plugin, action }
}

function isCoreConversionSelection(selection: ActionSelection) {
	return selection.plugin?.toLowerCase() === "showrunner" && Boolean(selection.action && isConversionActionId(selection.action))
}

function createFallbackCoreConversionAction(selection: ActionSelection) {
	if (!isCoreConversionSelection(selection) || !selection.action) return undefined
	const actionId = selection.action
	const resultMapping: Record<string, string> = { value: "value" }
	if (["convertStringToNumber", "convertStringToBoolean", "convertJsonStringToObject", "convertJsonStringToArray"].includes(actionId)) {
		resultMapping.converted = "converted"
	}
	return {
		id: nanoid(),
		plugin: "ShowRunner",
		action: actionId,
		config: defaultCoreConversionConfig(actionId),
		resultMapping,
	} as ActionInfo
}

function defaultCoreConversionConfig(actionId: string) {
	switch (actionId) {
		case "convertNumberToString":
		case "convertNumberToBoolean":
			return { value: 0 }
		case "convertBooleanToString":
		case "convertBooleanToNumber":
			return { value: false }
		case "convertStringToNumber":
			return { value: "", fallback: 0 }
		case "convertStringToBoolean":
			return { value: "", fallback: false }
		case "convertObjectToJsonString":
			return { value: {} }
		case "convertArrayToJsonString":
			return { value: [] }
		case "convertJsonStringToObject":
			return { value: "{}" }
		case "convertJsonStringToArray":
			return { value: "[]" }
		default:
			return {}
	}
}
