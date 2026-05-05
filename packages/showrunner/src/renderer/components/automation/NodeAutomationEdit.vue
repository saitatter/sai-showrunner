<template>
	<div class="node-automation">
		<header class="node-automation__toolbar">
			<div>
				<p class="node-automation__eyebrow">Automation Flow</p>
				<h2>{{ model.name || "Untitled Automation" }}</h2>
			</div>
		</header>

		<div class="node-automation__body">
			<section
				ref="canvasRef"
				class="node-automation__canvas"
				:class="{ panning: isPanning, 'space-held': spaceHeld }"
				role="application"
				aria-label="Node editor canvas"
				@pointerdown="handleCanvasPointerDown"
				@dragover.prevent="updateGhostNode"
				@dragleave="ghostNode = null"
				@drop.prevent="dropActionOnCanvas"
				@wheel.ctrl.prevent="zoomFromWheel"
				@wheel.shift.exact.prevent="horizontalPan"
				@contextmenu.prevent="openCanvasContextMenu"
			>
				<node-automation-canvas-controls
					:zoom="zoom"
					:zoom-step="ZOOM_STEP"
					:snap-to-grid="snapToGrid"
					:selected-node-count="selectedNodeIds.size"
					:is-preview-playing="isPreviewPlaying"
					:playhead-progress="playheadProgress"
					:current-preview-title="currentPreviewStep?.node.title"
					:current-preview-route-label="currentPreviewRouteLabel"
					:playhead-elapsed-label="playheadElapsedLabel"
					:preview-total-label="previewTotalLabel"
					:on-set-zoom="setZoom"
					:on-fit-graph="fitGraph"
					:on-fit-selection="fitToSelection"
					:on-reset-view="resetView"
					:on-toggle-snap-to-grid="toggleSnapToGrid"
					:on-auto-layout="autoLayout"
					:on-align-selected-nodes="alignSelectedNodes"
					:on-distribute-selected-nodes="distributeSelectedNodes"
					:on-add-annotation-block="addAnnotationBlock"
					:on-toggle-playhead-preview="togglePlayheadPreview"
					:on-reset-playhead-preview="resetPlayheadPreview"
				/>

				<node-automation-canvas-overlays
					ref="canvasOverlaysRef"
					v-model:canvas-search-query="canvasSearchQuery"
					:canvas-search-open="canvasSearchOpen"
					:canvas-search-index="canvasSearchIndex"
					:canvas-search-result-count="canvasSearchResults.length"
					:active-subgraph="activeSubgraph"
					:invalid-data-wire-issues="invalidDataWireIssues"
					:on-cycle-search-result="cycleSearchResult"
					:on-close-canvas-search="closeCanvasSearch"
					:on-open-main-canvas="openMainCanvas"
					:on-select-data-wire-issue="selectDataWireIssue"
					:on-cleanup-invalid-data-wires="cleanupInvalidDataWires"
				/>

				<div
					class="node-automation__surface"
					:style="{
						width: `${canvasSize.width}px`,
						height: `${canvasSize.height}px`,
						transform: `translate(${pan.x}px, ${pan.y}px) scale(${zoom})`,
					}"
				>
					<node-automation-annotation-blocks
						:blocks="annotationBlocks"
						:selected-block-id="selectedAnnotationBlockId"
						:annotation-block-style="annotationBlockStyle"
						:on-start-annotation-block-drag="startAnnotationBlockDrag"
						:on-start-annotation-block-resize="startAnnotationBlockResize"
						:on-select-annotation-block="selectAnnotationBlock"
					/>

					<node-automation-edges
						v-model:drop-target-edge-id="dropTargetEdgeId"
						:view-box="viewBox"
						:flow-edges="visibleFlowEdges"
						:data-wires="dataWirePaths"
						:drag-wire-path="dragWirePath"
						:exec-drag-wire-path="execDragWirePath"
						:alignment-guides="alignmentGuides"
						:selected-edge-id="selectedEdgeId"
						:selected-data-wire-id="selectedDataWireId"
						:removing-wire-ids="removingWireIds"
						:data-wire-title="dataWireTitle"
						:on-clear-drop-edge="clearDropEdge"
						:on-drop-action-on-edge="dropActionOnEdge"
						:on-start-exec-edge-drag="startExecEdgeDrag"
						:on-select-flow-edge="selectFlowEdge"
						:on-select-data-wire="selectDataWire"
					/>

					<node-automation-node-card
						v-for="node in nodes"
						:key="node.id"
						:node="node"
						:node-width="NODE_WIDTH"
						:selected="selectedNodeIds.has(node.id)"
						:drop-target="dropTargetNodeId === node.id"
						:preview-active="playheadNodeId === node.id"
						:search-match="canvasSearchMatchIds.has(node.id)"
						:search-dimmed="Boolean(canvasSearchQuery && !canvasSearchMatchIds.has(node.id))"
						:active-graph="Boolean(activeGraph)"
						:can-start-flow="canStartFlowFromNode(node)"
						:inline-edit-node-id="inlineEditNodeId"
						:active-test-execution="activeTestExecution"
						:is-port-connected="isPortConnected"
						:is-exec-port-connected="isExecPortConnected"
						:data-port-drag-class="dataPortDragClass"
						:data-port-drag-title="dataPortDragTitle"
						:format-node-duration="formatNodeDuration"
						:on-start-drag="startDrag"
						:on-select-node="selectNode"
						:on-open-subgraph-from-node="openSubgraphFromNode"
						:on-open-node-context="openNodeContext"
						:on-set-drop-target-node-id="setDropTargetNodeId"
						:on-clear-drop-target="clearDropTarget"
						:on-drop-action-on-node="dropActionOnNode"
						:on-start-inline-edit="startInlineEdit"
						:on-commit-inline-edit="commitInlineEdit"
						:on-cancel-inline-edit="cancelInlineEdit"
						:on-run-main-execution="runMainExecution"
						:on-start-wire-drag="startWireDrag"
						:on-start-exec-edge-drag="startExecEdgeDrag"
						:on-start-resize="startResize"
					/>

					<node-automation-canvas-drag-preview
						:ghost-node="ghostNode"
						:rubber-band="rubberBand"
					/>
				</div>

				<div
					v-if="contextMenu.open"
					ref="contextMenuRootRef"
					class="node-automation__context-menu-anchor"
					@keydown="handleContextMenuKeydown"
				>
					<node-automation-context-menu
						v-model:context-menu-query="contextMenuQuery"
						:context-menu="contextMenu"
						:context-menu-subtitle="contextMenuSubtitle"
						:recent-context-items="recentContextItems"
						:context-menu-search-results="contextMenuSearchResults"
						:hidden-plugin-search-hint="hiddenPluginSearchHint"
						:action-category-groups="actionCategoryGroups"
						:action-context-groups="actionContextGroups"
						:conversion-context-items="conversionContextItems"
						:trigger-context-groups="triggerContextGroups"
						:pending-flow-connection="Boolean(pendingFlowConnection)"
						:subgraphs-list="subgraphsList"
						:is-context-group-open="isContextGroupOpen"
						:toggle-context-group="toggleContextGroup"
						:on-close-context-menu="closeContextMenu"
						:on-select-action-from-context="selectActionFromContext"
						:on-select-trigger-from-context="selectTriggerFromContext"
						:on-select-context-search-result="selectContextSearchResult"
						:on-add-variable-node="addVariableNode"
						:on-add-control-flow-node="addControlFlowNode"
						:on-add-subgraph-call-node="addSubgraphCallNode"
					/>
				</div>
				<datalist id="node-expression-suggestions">
					<option v-for="item in expressionSuggestions" :key="item" :value="item" />
				</datalist>
				<node-automation-minimap
					:nodes="nodes"
					:edges="edges"
					:data-wires="dataWirePaths"
					:view-box="minimapViewBox"
					:viewport="minimapViewport"
					:node-width="NODE_WIDTH"
					:on-pointer-down="startMinimapNav"
				/>
			</section>

			<node-automation-details
				v-model:details-open="detailsOpen"
				v-model:config-open="configOpen"
				v-model:actions-open="actionsOpen"
				v-model:subgraphs-open="subgraphsOpen"
				v-model:action-palette-query="actionPaletteQuery"
				v-model:selected-action-to-add="selectedActionToAdd"
				:selected-node="selectedNode"
				:selected-annotation-block="selectedAnnotationBlock"
				:selected-action-info="selectedActionInfo"
				:selected-action-def="selectedActionDef"
				:selected-action-definition="selectedActionDefinition"
				:selected-action-path="selectedActionPath"
				:selected-action-missing="selectedActionMissing"
				:selected-trigger-missing="selectedTriggerMissing"
				:selected-trigger-config-model="selectedTriggerConfigModel"
				:selected-variable-node="selectedVariableNode"
				:selected-control-node="selectedControlNode"
				:selected-node-ids="selectedNodeIds"
				:action-palette="actionPalette"
				:flat-action-palette="flatActionPalette"
				:can-edit-selected-action="canEditSelectedAction"
				:focused-subgraph-id="focusedSubgraphId"
				:subgraphs-list="subgraphsList"
				:subgraph-param-types="SUBGRAPH_PARAM_TYPES"
				:active-test-execution="activeTestExecution"
				:on-clear-selection="clearSelection"
				:on-update-annotation-block-label="updateSelectedAnnotationBlockLabel"
				:on-update-annotation-block-color="updateSelectedAnnotationBlockColor"
				:on-delete-annotation-block="deleteSelectedAnnotationBlock"
				:on-update-variable-node-name="updateSelectedVariableNodeName"
				:on-update-variable-node-value="updateSelectedVariableNodeValue"
				:expression-mode="expressionMode"
				:expression-variable="expressionVariable"
				:expression-compare-value="expressionCompareValue"
				:expression-validation-message="expressionValidationMessage"
				:summarize-expression="summarizeExpression"
				:literal-number="literalNumber"
				:set-control-expression-mode="setControlExpressionMode"
				:set-control-expression-variable="setControlExpressionVariable"
				:set-control-expression-compare-value="setControlExpressionCompareValue"
				:set-control-string="setControlString"
				:set-control-number="setControlNumber"
				:set-control-literal-number="setControlLiteralNumber"
				:set-switch-case-value="setSwitchCaseValue"
				:add-switch-case="addSwitchCase"
				:delete-switch-case="deleteSwitchCase"
				:on-add-action-from-palette="addActionFromPalette"
				:on-start-action-palette-drag="startActionPaletteDrag"
				:on-duplicate-selected-action="duplicateSelectedAction"
				:on-move-selected-action="moveSelectedAction"
				:on-delete-selected-action="deleteSelectedAction"
				:on-reset-selected-node-position="resetSelectedNodePosition"
				:on-collapse-selection-to-subgraph="collapseSelectionToSubgraph"
				:can-move-selected-action="canMoveSelectedAction"
				:on-add-subgraph="addSubgraph"
				:on-focus-subgraph="focusSubgraph"
				:on-open-subgraph-canvas="openSubgraphCanvas"
				:on-delete-subgraph="deleteSubgraph"
				:on-update-subgraph-name="updateSubgraphName"
				:on-add-subgraph-param="addSubgraphParam"
				:on-delete-subgraph-param="deleteSubgraphParam"
				:on-update-subgraph-param="updateSubgraphParam"
				:on-add-subgraph-call-node="addSubgraphCallNode"
				:node-title-by-id="nodeTitleById"
				:format-node-duration="formatNodeDuration"
				@update:selected-action-def="updateSelectedActionDef"
				@update:selected-trigger-config-model="updateSelectedTriggerConfigModel"
			/>
			<div aria-live="polite" class="sr-only">{{ screenReaderAnnouncement }}</div>
		</div>

	</div>
</template>

<script setup lang="ts">
import { computed, nextTick, onMounted, onUnmounted, ref, useModel, watch } from "vue"
import { nanoid } from "nanoid"
import {
	ActionSelection,
	AutomationConfig,
	AutomationResourceView,
	useCommitUndo,
	usePluginStore,
	useActionQueueStore,
} from "showrunner-ui-core"
import {
	ActionInfo,
	constructDefault,
	type AutomationDataWire,
	type GraphNode,
	type GraphEdge,
} from "showrunner-schema"
import { useNodeCanvas, type NodeEditorViewState, type NodePosition } from "./useNodeCanvas"
import { isConversionActionId, useNodeContextMenu } from "./useNodeContextMenu"
import { useNodeContextMenuSearch, type ContextSearchResult } from "./useNodeContextMenuSearch"
import { useNodeDrag } from "./useNodeDrag"
import { useAnnotationBlocks, type AnnotationBlock } from "./useAnnotationBlocks"
import { useVariableNodes } from "./useVariableNodes"
import { useGraphTriggerNodes } from "./useGraphTriggerNodes"
import { useAutomationPreview } from "./useAutomationPreview"
import { usePortConnections } from "./usePortConnections"
import { useDataWireHealth } from "./useDataWireHealth"
import { useExecEdges } from "./useExecEdges"
import { useClipboard } from "./useClipboard"
import {
	addGraphActionNode as addGraphActionNodeToGraph,
	connectFlowToNode as connectGraphFlowToNode,
	insertActionInGraph,
	insertActionOnGraphEdge,
	resolveContextActionPosition,
} from "./automation-graph-editing"
import { EXPRESSION_BUILTINS } from "./expression-tokenizer"
import {
	type NodeData,
	type EdgeData,
	NODE_WIDTH,
	H_GAP,
	GRAPH_NODE_INFO,
	summarizeExpression,
	buildGraph,
	buildGraphFromAutomationGraph,
	getNodeLane,
} from "./useNodeRendering"
import NodeAutomationDetails from "./NodeAutomationDetails.vue"
import NodeAutomationContextMenu from "./NodeAutomationContextMenu.vue"
import NodeAutomationCanvasControls from "./NodeAutomationCanvasControls.vue"
import NodeAutomationMinimap from "./NodeAutomationMinimap.vue"
import NodeAutomationCanvasOverlays from "./NodeAutomationCanvasOverlays.vue"
import NodeAutomationEdges from "./NodeAutomationEdges.vue"
import NodeAutomationAnnotationBlocks from "./NodeAutomationAnnotationBlocks.vue"
import NodeAutomationNodeCard from "./NodeAutomationNodeCard.vue"
import NodeAutomationCanvasDragPreview from "./NodeAutomationCanvasDragPreview.vue"
import { useCanvasSelection, type RubberBand } from "./useCanvasSelection"
import { useCanvasKeyboard } from "./useCanvasKeyboard"
import { SUBGRAPH_PARAM_TYPES, useSubgraphManagement } from "./useSubgraphManagement"
import { useControlFlowNodes } from "./useControlFlowNodes"
import { useSubgraphCollapse } from "./useSubgraphCollapse"
import { useNodeResize } from "./useNodeResize"
import { resolveActionDefinition } from "./actionLookup"

const props = defineProps<{
	modelValue: AutomationConfig
	view: AutomationResourceView & {
		nodePositions?: Record<string, NodePosition>
		nodeView?: NodeEditorViewState
		nodeSizes?: Record<string, { width?: number; height?: number }>
		annotationBlocks?: AnnotationBlock[]
	}
}>()

const model = useModel(props, "modelValue")
const view = useModel(props, "view")
const selectedNodeId = ref<string>()
const selectedNodeIds = ref<Set<string>>(new Set())
const selectedAnnotationBlockId = ref<string>()
const selectedActionToAdd = ref("")
const actionPaletteQuery = ref("")
const dropTargetNodeId = ref<string>()
const dropTargetEdgeId = ref<string>()
const selectedEdgeId = ref<string>()
const spaceHeld = ref(false)
const ghostNode = ref<{ x: number; y: number } | null>(null)
const rubberBand = ref<RubberBand | null>(null)
const canvasSearchOpen = ref(false)
const canvasSearchQuery = ref("")
const canvasSearchIndex = ref(0)
const canvasOverlaysRef = ref<InstanceType<typeof NodeAutomationCanvasOverlays>>()
const contextMenuRootRef = ref<HTMLElement>()
const detailsOpen = ref(true)
const configOpen = ref(true)
const actionsOpen = ref(false)
const subgraphsOpen = ref(false)
const focusedSubgraphId = ref<string>()
const activeSubgraphId = ref<string>()
const recentlyUsed = ref<{ key: string; kind: "action" | "trigger"; name: string; icon: string; color: string }[]>([])
const pendingFlowConnection = ref<{ fromNode: string; fromPort?: string; canvasPoint: NodePosition } | null>(null)
const recentContextItems = computed(() =>
	(pendingFlowConnection.value ? recentlyUsed.value.filter((item) => item.kind === "action") : recentlyUsed.value)
		.filter((item) => isPluginEnabledForContextKey(item.key))
)
const MAX_RECENT = 5
const pluginStore = usePluginStore()
const commitUndo = useCommitUndo()
const actionQueueStore = useActionQueueStore()
const activeTestExecutionId = ref<string>()
const activeTestExecution = computed(() => {
	if (!activeTestExecutionId.value) return undefined
	return actionQueueStore.activeTestExecutions[activeTestExecutionId.value]
})
let canvasSelection: ReturnType<typeof useCanvasSelection>
const {
	subgraphsList,
	activeSubgraph,
	isEditingSubgraph,
	activeGraph,
	addSubgraph,
	focusSubgraph,
	openSubgraphCanvas,
	openMainCanvas,
	deleteSubgraph,
	updateSubgraphName,
	addSubgraphParam,
	deleteSubgraphParam,
	updateSubgraphParam,
} = useSubgraphManagement({
	model,
	focusedSubgraphId,
	activeSubgraphId,
	subgraphsOpen,
	clearSelection,
	closeContextMenu,
	commitUndo,
})

const nodePositions = computed(() => {
	if (!view.value) return {}
	view.value.nodePositions ??= {}
	return view.value.nodePositions
})
const nodeSizes = computed(() => {
	if (!view.value) return {}
	view.value.nodeSizes ??= {}
	return view.value.nodeSizes!
})
const dataWires = computed({
	get: () => {
		if (!model.value) return []
		if (activeSubgraph.value) {
			activeSubgraph.value.dataWires ??= []
			return activeSubgraph.value.dataWires
		}
		model.value.dataWires ??= []
		return model.value.dataWires!
	},
	set: (v: AutomationDataWire[]) => {
		if (!model.value) return
		if (activeSubgraph.value) {
			activeSubgraph.value.dataWires = v
			return
		}
		model.value.dataWires = v
	},
})
const {
	variableNodes,
	variableNodeData,
	selectedVariableNode,
	inlineEditNodeId,
	addVariableNode,
	deleteVariableNode,
	updateSelectedVariableNodeValue,
	updateSelectedVariableNodeName,
	startInlineEdit,
	commitInlineEdit,
	cancelInlineEdit,
} = useVariableNodes({
	model,
	nodePositions,
	nodeSizes,
	dataWires,
	selectedNodeId,
	getContextMenuCanvasPoint: () => contextMenu.value.canvasPoint ?? { x: 100, y: 200 },
	closeContextMenu,
	commitUndo,
})

const graph = computed(() => {
	if (activeSubgraph.value) {
		return buildGraphFromAutomationGraph(activeSubgraph.value, pluginStore.pluginMap, model.value.subgraphs ?? [])
	}
	return buildGraph(model.value, pluginStore.pluginMap, getPreviewConfiguredDurationSeconds)
})
const nodes = computed(() => {
	const actionNodes = graph.value.nodes.map((node) => ({
		...node,
		...(nodePositions.value[node.id] ?? { x: node.x, y: node.y }),
		width: nodeSizes.value[node.id]?.width ?? NODE_WIDTH,
		height: Math.max(node.height, nodeSizes.value[node.id]?.height ?? node.height),
	}))
	return [...actionNodes, ...variableNodeData.value]
})
const canvasSearchResults = computed(() => {
	const q = canvasSearchQuery.value.toLowerCase().trim()
	if (!q) return []
	return nodes.value.filter((n) => {
		const text = `${n.title} ${n.subtitle} ${n.kind} ${n.badge ?? ""} ${(n.configLines ?? []).map((l) => `${l.label} ${l.value}`).join(" ")}`.toLowerCase()
		return text.includes(q)
	})
})
const canvasSearchMatchIds = computed(() => new Set(canvasSearchResults.value.map((n) => n.id)))
const screenReaderAnnouncement = computed(() => {
	if (selectedNodeIds.value.size === 0) return ""
	if (selectedNodeIds.value.size === 1) {
		const node = nodes.value.find((n) => n.id === selectedNodeId.value)
		return node ? `Selected ${node.kind} node: ${node.title}` : ""
	}
	return `${selectedNodeIds.value.size} nodes selected`
})
const edges = computed<EdgeData[]>(() => {
	if (!activeGraph.value) return []
	// Build edges from the graph data, computing SVG paths
	const nodeMap = new Map(nodes.value.map((n) => [n.id, n]))
	return graph.value.edges.map((e) => {
		const fromNode = nodeMap.get(e.from)
		const toNode = nodeMap.get(e.to)
		const fromX = fromNode ? fromNode.x + (fromNode.width ?? NODE_WIDTH) : 0
		const fromY = fromNode ? fromNode.y + fromNode.height / 2 : 0
		const toX = toNode ? toNode.x : 0
		const toY = toNode ? toNode.y + toNode.height / 2 : 0
		const cpOffset = Math.min(80, Math.abs(toX - fromX) / 2)
		const path = `M${fromX},${fromY} C${fromX + cpOffset},${fromY} ${toX - cpOffset},${toY} ${toX},${toY}`
		const label = getEdgeLabel(e)
		return {
			id: e.id,
			from: e.from,
			to: e.to,
			port: e.port,
			label,
			labelWidth: getEdgeLabelWidth(label),
			labelX: (fromX + toX) / 2,
			labelY: (fromY + toY) / 2 - 10,
			path,
		}
	}).filter((e) => e.path)
})
const visibleFlowEdges = computed(() => edges.value)
const currentPreviewRouteLabel = computed(() => {
	const nodeId = currentPreviewStep.value?.node.id
	if (!nodeId || !activeGraph.value) return undefined
	const incoming = activeGraph.value.edges.find((edge) => edge.to === nodeId)
	return incoming ? getEdgeLabel(incoming) : undefined
})
const selectedNode = computed(() => nodes.value.find((node) => node.id === selectedNodeId.value))
const selectedControlNode = computed(() => {
	if (!selectedNodeId.value) return undefined
	const node = activeGraph.value?.nodes.find((item) => item.id === selectedNodeId.value)
	return node && node.type !== "action" ? node : undefined
})
const previewNodes = computed(() => nodes.value.filter((node) => node.id !== "trigger").sort((a, b) => a.x - b.x || a.y - b.y))
const expressionSuggestions = computed(() => {
	const suggestions = new Set<string>()
	for (const node of variableNodes.value) {
		if (node.name) suggestions.add(node.name)
	}
	for (const port of nodes.value.find((node) => node.id === "trigger")?.outputPorts ?? []) {
		suggestions.add(port.key)
	}
	for (const node of nodes.value) {
		for (const port of node.outputPorts ?? []) {
			if (port.type !== "flow") suggestions.add(`${node.id}.${port.key}`)
		}
	}
	for (const builtin of EXPRESSION_BUILTINS) {
		suggestions.add(`${builtin}(...)`)
	}
	return [...suggestions].sort((a, b) => a.localeCompare(b))
})
const {
	playheadNodeId,
	isPreviewPlaying,
	playheadProgress,
	currentPreviewStep,
	playheadElapsedLabel,
	previewTotalLabel,
	togglePlayheadPreview,
	pausePlayheadPreview,
	resetPlayheadPreview,
	getConfiguredDurationSeconds: getPreviewConfiguredDurationSeconds,
} = useAutomationPreview(model, previewNodes)
const selectedActionInfo = computed(() => {
	if (!selectedNodeId.value || selectedNodeId.value === "trigger") return undefined
	const index = activeGraph.value?.nodes.findIndex((node) => node.id === selectedNodeId.value && node.type === "action") ?? -1
	if (index < 0) return undefined
	return activeGraph.value!.nodes[index] as Extract<GraphNode, { type: "action" }>
})
const selectedActionPath = computed(() => {
	if (!selectedActionInfo.value || !activeGraph.value) return undefined
	const index = activeGraph.value.nodes.findIndex((node) => node.id === selectedActionInfo.value?.id)
	if (index < 0) return undefined
	return activeSubgraph.value ? `subgraphs[${model.value.subgraphs?.findIndex((sg) => sg.id === activeSubgraph.value?.id) ?? 0}].nodes[${index}]` : `graph.nodes[${index}]`
})
const selectedActionDef = computed(() => {
	return selectedActionInfo.value
})
const selectedActionDefinition = computed(() => {
	const action = selectedActionInfo.value
	return resolveActionDefinition(pluginStore.pluginMap, action?.plugin, action?.action)
})
function updateSelectedActionDef(value: ActionInfo | undefined) {
	if (!value || !selectedActionInfo.value) return
	Object.assign(selectedActionInfo.value, value)
}
const selectedActionMissing = computed(() => {
	if (!selectedActionInfo.value) return false
	return !selectedActionDefinition.value
})
const canEditSelectedAction = computed(() => {
	return Boolean(selectedActionInfo.value)
})
const actionPalette = computed(() =>
	[...pluginStore.pluginMap.values()]
		.filter((plugin) => pluginStore.isPluginEnabled(plugin.id))
		.map((plugin) => ({
			id: plugin.id,
			name: plugin.name,
			actions: Object.values(plugin.actions)
				.filter((action) => action.type === "regular")
				.map((action) => ({
					key: `${plugin.id}:${action.id}`,
					name: action.name,
					searchText: `${plugin.name} ${plugin.id} ${action.name} ${action.id}`.toLowerCase(),
				}))
				.filter((action) => action.searchText.includes(actionPaletteSearch.value))
				.sort((a, b) => a.name.localeCompare(b.name)),
		}))
		.filter((plugin) => plugin.actions.length || plugin.name.toLowerCase().includes(actionPaletteSearch.value))
		.sort((a, b) => a.name.localeCompare(b.name))
)
const actionPaletteSearch = computed(() => actionPaletteQuery.value.trim().toLowerCase())
const flatActionPalette = computed(() =>
	actionPalette.value
		.flatMap((plugin) => plugin.actions.map((action) => ({ ...action, pluginName: plugin.name })))
		.slice(0, 24)
)
const viewBox = computed(() => {
	return `0 0 ${canvasSize.value.width} ${canvasSize.value.height}`
})
const canvasSize = computed(() => ({
	width: Math.max(
		1280,
		...nodes.value.map((node) => node.x + (node.width ?? NODE_WIDTH) + 160),
		...annotationBlocks.value.map((block) => block.x + block.width + 160)
	),
	height: Math.max(720, ...nodes.value.map((node) => node.y + node.height + 160), ...annotationBlocks.value.map((block) => block.y + block.height + 160)),
}))
const graphBounds = computed(() => {
	const minX = Math.min(42, ...nodes.value.map((node) => node.x), ...annotationBlocks.value.map((block) => block.x))
	const minY = Math.min(88, ...nodes.value.map((node) => node.y), ...annotationBlocks.value.map((block) => block.y))
	const maxX = Math.max(
		...nodes.value.map((node) => node.x + (node.width ?? NODE_WIDTH)),
		...annotationBlocks.value.map((block) => block.x + block.width)
	)
	const maxY = Math.max(...nodes.value.map((node) => node.y + node.height), ...annotationBlocks.value.map((block) => block.y + block.height))
	return { minX, minY, width: maxX - minX, height: maxY - minY }
})
const MINIMAP_PADDING = 40
const minimapViewBox = computed(() => {
	const b = graphBounds.value
	return `${b.minX - MINIMAP_PADDING} ${b.minY - MINIMAP_PADDING} ${b.width + MINIMAP_PADDING * 2} ${b.height + MINIMAP_PADDING * 2}`
})
const minimapViewport = computed(() => {
	const canvas = canvasRef.value
	if (!canvas) return { x: 0, y: 0, width: 400, height: 300 }
	const scrollLeft = canvas.scrollLeft
	const scrollTop = canvas.scrollTop
	const w = canvas.clientWidth
	const h = canvas.clientHeight
	const z = zoom.value
	const px = pan.value.x
	const py = pan.value.y
	return {
		x: (scrollLeft - px) / z,
		y: (scrollTop - py) / z,
		width: w / z,
		height: h / z,
	}
})
const {
	annotationBlocks,
	selectedAnnotationBlock,
	addAnnotationBlock,
	annotationBlockStyle,
	startAnnotationBlockDrag,
	startAnnotationBlockResize,
	updateSelectedAnnotationBlockLabel,
	updateSelectedAnnotationBlockColor,
	deleteSelectedAnnotationBlock,
} = useAnnotationBlocks({
	view,
	nodes,
	selectedNodeIds,
	selectedAnnotationBlockId,
	getZoom: () => zoom.value,
	snapCoordinate: (value) => snapCoordinate(value),
	getViewport: () => minimapViewport.value,
	selectAnnotationBlock,
	commitUndo,
})
const {
	canvasRef,
	zoom,
	pan,
	isPanning,
	snapToGrid,
	ZOOM_STEP,
	setZoom,
	toggleSnapToGrid,
	snapCoordinate,
	zoomFromWheel,
	horizontalPan,
	fitGraph,
	resetView,
	fitSelection,
	startPan,
	getCanvasPointFromClient: getCanvasPointFromClientPosition,
} = useNodeCanvas(view, graphBounds, commitUndo)
const graphRef = computed(() => activeGraph.value)
const {
	execEdgeDrag,
	execDragWirePath,
	startExecEdgeDrag,
	deleteExecEdge,
} = useExecEdges(graphRef, nodes, canvasRef, zoom, commitUndo, openPendingFlowContext)
const {
	copySelectedNodes,
	cutSelectedNodes,
	pasteNodes,
} = useClipboard(model, graphRef, selectedNodeIds, selectedNodeId, variableNodes, dataWires, nodePositions, canvasRef, zoom, commitUndo, clearSelection)
const {
	contextMenu,
	contextMenuQuery,
	contextMenuSubtitle,
	actionContextGroups,
	actionCategoryGroups,
	conversionContextItems,
	triggerContextGroups,
	contextMenuSearchItems,
	disabledContextMenuSearchItems,
	openContextMenu,
	openContextMenuAt,
	closeContextMenu: closeContextMenuBase,
	toggleContextGroup,
	isContextGroupOpen,
} = useNodeContextMenu(nodes, pluginStore, getCanvasPointFromClient, getNodeLane)

const {
	selectedTriggerConfigModel,
	selectedTriggerMissing,
	selectTriggerFromContext,
} = useGraphTriggerNodes({
	model,
	selectedNode,
	selectedNodeId,
	pluginStore,
	getContextMenuCanvasPoint: () => contextMenu.value.canvasPoint,
	trackRecentlyUsed,
	focusNode,
	closeContextMenu,
	commitUndo,
	configOpen,
})

function updateSelectedTriggerConfigModel(value: typeof selectedTriggerConfigModel.value) {
	selectedTriggerConfigModel.value = value
}

const {
	contextMenuFocusIndex,
	contextMenuSearchResults,
	hiddenPluginSearchHint,
	handleContextMenuKeydown,
	resetContextMenuFocus,
} = useNodeContextMenuSearch({
	contextMenu,
	contextMenuQuery,
	contextMenuRootRef,
	contextMenuSearchItems,
	disabledContextMenuSearchItems,
	pendingFlowConnection,
	subgraphsList,
	closeContextMenu,
	toggleContextGroup,
	isContextGroupOpen,
})

watch(
	() => contextMenu.value.open,
	(open) => {
		if (!open) return
		resetContextMenuFocus()
		nextTick(() => {
			contextMenuRootRef.value?.querySelector<HTMLInputElement>("input[type='search']")?.focus()
		})
	}
)

watch(contextMenuQuery, () => {
	resetContextMenuFocus()
})

function closeContextMenu() {
	pendingFlowConnection.value = null
	closeContextMenuBase()
}

function isPluginEnabledForContextKey(key: string) {
	const [pluginId] = key.split(":")
	return !pluginId || pluginStore.isPluginEnabled(pluginId)
}

const { startDrag, resetSelectedNodePosition, alignmentGuides } = useNodeDrag(
	nodePositions,
	selectedNodeId,
	selectedNodeIds,
	zoom,
	snapCoordinate,
	closeContextMenu,
	commitUndo,
	nodes,
	NODE_WIDTH
)
const {
	wireDrag,
	dataWirePaths,
	dragWirePath,
	dragPortPreview,
	startWireDrag,
	deleteDataWire,
} = usePortConnections(nodes, dataWires, zoom, pan, canvasRef, commitUndo)
const {
	selectedDataWireId,
	invalidDataWireIssues,
	isPortConnected,
	selectDataWireIssue,
	cleanupInvalidDataWires,
	dataWireTitle,
	selectDataWire: selectDataWireBase,
} = useDataWireHealth({
	nodes,
	dataWires,
	variableNodes,
	activeSubgraph,
	activeTestExecution,
	selectedEdgeId,
	selectedNodeId,
	selectedNodeIds,
	commitUndo,
	nodeTitleById,
})

canvasSelection = useCanvasSelection({
	nodes,
	canvasRef,
	selectedNodeId,
	selectedNodeIds,
	selectedAnnotationBlockId,
	selectedEdgeId,
	selectedDataWireId,
	detailsOpen,
	spaceHeld,
	rubberBand,
	contextMenuOpen: () => contextMenu.value.open,
	closeContextMenu,
	startPan,
	getCanvasPointFromClientPosition,
})

const {
	handleKeydown,
	handleKeyup,
	openCanvasSearch,
	closeCanvasSearch,
	cycleSearchResult,
	scrollToNode,
} = useCanvasKeyboard({
	nodes,
	selectedNode,
	selectedNodeId,
	selectedNodeIds,
	selectedEdgeId,
	selectedDataWireId,
	activeGraph,
	canEditSelectedAction,
	spaceHeld,
	canvasRef,
	canvasSearchOpen,
	canvasSearchQuery,
	canvasSearchIndex,
	canvasSearchResults,
	canvasOverlaysRef,
	nodePositions,
	zoom,
	pan,
	zoomStep: ZOOM_STEP,
	contextMenuOpen: () => contextMenu.value.open,
	closeContextMenu,
	focusNode,
	deleteSelectedAction,
	deleteVariableNode,
	deleteSelectedEdge,
	animateWireRemoval,
	duplicateSelectedAction,
	copySelectedNodes,
	cutSelectedNodes,
	pasteNodes,
	setZoom,
	resetView,
	fitGraph,
})

const {
	addControlFlowNode,
	expressionMode,
	expressionVariable,
	expressionCompareValue,
	expressionValidationMessage,
	literalNumber,
	setControlExpressionMode,
	setControlExpressionVariable,
	setControlExpressionCompareValue,
	setControlString,
	setControlNumber,
	setControlLiteralNumber,
	setSwitchCaseValue,
	addSwitchCase,
	deleteSwitchCase,
} = useControlFlowNodes({
	getContextMenuCanvasPoint: () => contextMenu.value.canvasPoint,
	pendingFlowConnection,
	ensureGraph,
	connectFlowToNode,
	closeContextMenu,
	commitUndo,
})

const {
	collapseSelectionToSubgraph,
} = useSubgraphCollapse({
	model,
	activeGraph,
	selectedNodeIds,
	dataWires,
	nodes,
	focusedSubgraphId,
	subgraphsOpen,
	focusNode,
	commitUndo,
})

const {
	startResize,
} = useNodeResize({
	nodeSizes,
	zoom,
	commitUndo,
})


function dataPortDragClass(nodeId: string, portKey: string, kind: "in" | "out") {
	const preview = dragPortPreview.value
	if (!preview || preview.nodeId !== nodeId || preview.portKey !== portKey || preview.kind !== kind) return undefined
	return preview.valid ? "drag-valid" : "drag-invalid"
}

function dataPortDragTitle(nodeId: string, portKey: string, kind: "in" | "out") {
	const preview = dragPortPreview.value
	if (!preview || preview.nodeId !== nodeId || preview.portKey !== portKey || preview.kind !== kind) return undefined
	return preview.message ?? "Release to connect this data port."
}

function isExecPortConnected(nodeId: string, portKey: string): boolean {
	if (!activeGraph.value) return false
	return activeGraph.value.edges.some((e) => e.from === nodeId && e.port === portKey)
}

function canStartFlowFromNode(node: NodeData) {
	return Boolean(activeGraph.value && node.kind !== "variable")
}

function getEdgeLabel(edgeOrPort?: { from?: string; port?: string } | string) {
	const from = typeof edgeOrPort === "string" ? undefined : edgeOrPort?.from
	const port = typeof edgeOrPort === "string" ? edgeOrPort : edgeOrPort?.port
	if (!port) return undefined
	if (port === "then") return "then"
	if (port === "else") return "else"
	if (port === "default") return "default"
	if (port === "body") return "loop body"
	if (port === "next") return "done"
	if (port.startsWith("case:")) {
		const source = activeGraph.value?.nodes.find((node) => node.id === from && node.type === "switch")
		const match = source?.type === "switch" ? source.cases.find((item) => item.port === port) : undefined
		return match ? `case: ${String(match.value)}` : `case ${port.slice(5)}`
	}
	return port
}

function getEdgeLabelWidth(label?: string) {
	if (!label) return undefined
	return Math.max(60, Math.min(150, label.length * 8 + 24))
}

const removingWireIds = ref(new Set<string>())

function animateWireRemoval(wireId: string) {
	removingWireIds.value.add(wireId)
	setTimeout(() => {
		removingWireIds.value.delete(wireId)
		deleteDataWire(wireId)
	}, 300)
}


function selectNode(event: MouseEvent | PointerEvent, nodeId: string) {
	canvasSelection.selectNode(event, nodeId)
}

function focusNode(nodeId: string) {
	canvasSelection.focusNode(nodeId)
}

function clearSelection() {
	canvasSelection.clearSelection()
}

function clearNodeSelection() {
	canvasSelection.clearNodeSelection()
}

function selectFlowEdge(edgeId: string) {
	clearNodeSelection()
	selectedDataWireId.value = undefined
	selectedEdgeId.value = edgeId
}

function selectDataWire(wireId: string) {
	selectDataWireBase(wireId, clearNodeSelection)
}

function selectAnnotationBlock(blockId: string) {
	canvasSelection.selectAnnotationBlock(blockId)
}

function openPendingFlowContext(drop: {
	fromNode: string
	fromPort?: string
	canvasPoint: NodePosition
	clientPoint: { x: number; y: number }
}) {
	pendingFlowConnection.value = {
		fromNode: drop.fromNode,
		fromPort: drop.fromPort,
		canvasPoint: drop.canvasPoint,
	}
	clearSelection()
	actionsOpen.value = true
	openContextMenuAt(drop.clientPoint.x, drop.clientPoint.y, drop.canvasPoint)
}

function openNodeContext(event: MouseEvent, node: NodeData) {
	pendingFlowConnection.value = null
	selectNode(event, node.id)
	detailsOpen.value = true
	configOpen.value = true
	actionsOpen.value = false
	openContextMenu(event, node.id)
}

function openCanvasContextMenu(event: MouseEvent) {
	const target = event.target as HTMLElement
	if (target.closest(".node-automation__canvas-controls") || target.closest(".node-automation__context-menu")) return
	if (target.closest(".node-automation__annotation-block")) return
	const nodeElement = target.closest(".node-automation__node")
	if (nodeElement) return
	pendingFlowConnection.value = null
	clearSelection()
	openContextMenu(event)
}

function handleCanvasPointerDown(event: PointerEvent) {
	canvasSelection.handleCanvasPointerDown(event)
}

function startMinimapNav(event: PointerEvent) {
	const svg = event.currentTarget as SVGSVGElement
	if (!svg || !canvasRef.value) return

	function navToPoint(clientX: number, clientY: number) {
		const canvas = canvasRef.value!
		const pt = svg.createSVGPoint()
		pt.x = clientX
		pt.y = clientY
		const ctm = svg.getScreenCTM()
		if (!ctm) return
		const svgPt = pt.matrixTransform(ctm.inverse())
		const z = zoom.value
		const px = pan.value.x
		const py = pan.value.y
		canvas.scrollTo({
			left: Math.max(0, svgPt.x * z + px - canvas.clientWidth / 2),
			top: Math.max(0, svgPt.y * z + py - canvas.clientHeight / 2),
		})
	}

	navToPoint(event.clientX, event.clientY)
	svg.setPointerCapture(event.pointerId)

	function onMove(e: PointerEvent) {
		navToPoint(e.clientX, e.clientY)
	}
	function onUp(e: PointerEvent) {
		svg.releasePointerCapture(e.pointerId)
		svg.removeEventListener("pointermove", onMove)
		svg.removeEventListener("pointerup", onUp)
		svg.removeEventListener("pointercancel", onUp)
	}
	svg.addEventListener("pointermove", onMove)
	svg.addEventListener("pointerup", onUp)
	svg.addEventListener("pointercancel", onUp)
}

function autoLayout() {
	commitUndo()
	const graphNodes = graph.value.nodes
	const positions = { ...nodePositions.value }
	for (const node of graphNodes) {
		positions[node.id] = { x: node.x, y: node.y }
	}
	view.value = { ...view.value, nodePositions: positions }
}

function fitToSelection() {
	const selected = nodes.value.filter((n) => selectedNodeIds.value.has(n.id))
	if (!selected.length) return
	const minX = Math.min(...selected.map((n) => n.x))
	const minY = Math.min(...selected.map((n) => n.y))
	const maxX = Math.max(...selected.map((n) => n.x + (n.width ?? NODE_WIDTH)))
	const maxY = Math.max(...selected.map((n) => n.y + n.height))
	fitSelection({ minX, minY, width: maxX - minX, height: maxY - minY })
}

function alignSelectedNodes(axis: "horizontal" | "vertical") {
	if (selectedNodeIds.value.size < 2) return
	commitUndo()
	const selected = nodes.value.filter((n) => selectedNodeIds.value.has(n.id))
	const positions = { ...nodePositions.value }

	if (axis === "horizontal") {
		// Align all selected to the average Y
		const avgY = selected.reduce((sum, n) => sum + n.y + n.height / 2, 0) / selected.length
		for (const node of selected) {
			positions[node.id] = { x: (positions[node.id] ?? node).x, y: avgY - node.height / 2 }
		}
	} else {
		// Align all selected to the average X
		const avgX = selected.reduce((sum, n) => sum + n.x + (n.width ?? NODE_WIDTH) / 2, 0) / selected.length
		for (const node of selected) {
			positions[node.id] = { x: avgX - (node.width ?? NODE_WIDTH) / 2, y: (positions[node.id] ?? node).y }
		}
	}
	view.value = { ...view.value, nodePositions: positions }
}

function distributeSelectedNodes() {
	if (selectedNodeIds.value.size < 3) return
	commitUndo()
	const selected = nodes.value.filter((n) => selectedNodeIds.value.has(n.id))
	const positions = { ...nodePositions.value }

	// Determine if nodes are more horizontal or vertical
	const xs = selected.map((n) => n.x)
	const ys = selected.map((n) => n.y)
	const xRange = Math.max(...xs) - Math.min(...xs)
	const yRange = Math.max(...ys) - Math.min(...ys)

	if (xRange >= yRange) {
		// Distribute horizontally
		const sorted = [...selected].sort((a, b) => a.x - b.x)
		const minX = sorted[0].x
		const maxX = sorted[sorted.length - 1].x
		const step = (maxX - minX) / (sorted.length - 1)
		for (let i = 0; i < sorted.length; i++) {
			positions[sorted[i].id] = { x: minX + step * i, y: (positions[sorted[i].id] ?? sorted[i]).y }
		}
	} else {
		// Distribute vertically
		const sorted = [...selected].sort((a, b) => a.y - b.y)
		const minY = sorted[0].y
		const maxY = sorted[sorted.length - 1].y
		const step = (maxY - minY) / (sorted.length - 1)
		for (let i = 0; i < sorted.length; i++) {
			positions[sorted[i].id] = { x: (positions[sorted[i].id] ?? sorted[i]).x, y: minY + step * i }
		}
	}
	view.value = { ...view.value, nodePositions: positions }
}

function handleWindowClick(event: MouseEvent) {
	const target = event.target as HTMLElement | null
	if (target?.closest(".node-automation__context-menu")) return
	if (contextMenu.value.open) closeContextMenu()
}

function parseActionSelection(value: string): ActionSelection | undefined {
	const [plugin, action] = value.split(":")
	if (!plugin || !action) return undefined
	return { plugin, action }
}

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
	} finally { dropInProgress = false }
}

function trackRecentlyUsed(key: string, kind: "action" | "trigger", name: string, icon: string, color: string) {
	recentlyUsed.value = [{ key, kind, name, icon, color }, ...recentlyUsed.value.filter((r) => r.key !== key)].slice(0, MAX_RECENT)
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
	const position = resolveContextActionPosition(pendingFlow, contextMenu.value, contextAnchorNode, H_GAP)
	insertAction(action, pendingFlow?.fromNode ?? contextMenu.value.nodeId, position, pendingFlow?.fromPort)
	if (position) nodePositions.value[action.id] = position
	focusNode(action.id)
	configOpen.value = true
	closeContextMenu()
	commitUndo()
	} finally { dropInProgress = false }
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

async function selectContextSearchResult(item: ContextSearchResult) {
	switch (item.kind) {
		case "action":
			await selectActionFromContext(item.key)
			break
		case "trigger":
			await selectTriggerFromContext(item.key)
			break
		case "variable":
			addVariableNode(item.variableType)
			break
		case "control":
			addControlFlowNode(item.controlType)
			break
		case "subgraph":
			addSubgraphCallNode(item.subgraphId)
			break
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
	} finally { dropInProgress = false }
}

async function dropActionOnNode(event: DragEvent, node: NodeData) {
	if (dropInProgress) return
	dropInProgress = true
	try {
	const action = await createDraggedAction(event)
	if (!action) return

	const position = {
		x: snapCoordinate(node.x + H_GAP),
		y: snapCoordinate(node.y),
	}
	insertAction(action, node.id, position)
	nodePositions.value[action.id] = position
	focusNode(action.id)
	configOpen.value = true
	dropTargetNodeId.value = undefined
	commitUndo()
	} finally { dropInProgress = false }
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
	} finally { dropInProgress = false }
}

function clearDropTarget(nodeId: string) {
	if (dropTargetNodeId.value === nodeId) dropTargetNodeId.value = undefined
}

function setDropTargetNodeId(nodeId: string) {
	dropTargetNodeId.value = nodeId
}

function clearDropEdge(edgeId: string) {
	if (dropTargetEdgeId.value === edgeId) dropTargetEdgeId.value = undefined
}

async function createDraggedAction(event: DragEvent) {
	const actionKey =
		event.dataTransfer?.getData("application/showrunner-action") || event.dataTransfer?.getData("text/plain")
	const selection = parseActionSelection(actionKey || "")
	if (!selection) return undefined
	return pluginStore.createAction(selection)
}

function ensureGraph() {
	if (activeSubgraph.value) return activeSubgraph.value
	model.value.graph ??= { nodes: [], edges: [], entryNodeId: "" }
	return model.value.graph
}

function addGraphActionNode(action: ActionInfo, position: NodePosition) {
	return addGraphActionNodeToGraph(ensureGraph(), action, position)
}

function connectFlowToNode(fromNode: string, fromPort: string | undefined, toNode: string, isTerminal = false) {
	connectGraphFlowToNode(ensureGraph(), fromNode, fromPort, toNode, isTerminal)
}

function insertAction(action: ActionInfo, afterNodeId = selectedNodeId.value, position?: NodePosition, afterPort?: string) {
	return insertActionInGraph(ensureGraph(), action, {
		afterNodeId,
		afterPort,
		position,
		anchorNodes: nodes.value,
		snapCoordinate,
		anchorOffsetX: H_GAP,
	})
}

function insertActionOnEdge(action: ActionInfo, edge: EdgeData, position: NodePosition) {
	return insertActionOnGraphEdge(ensureGraph(), action, edge, position)
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
		x: snapCoordinate((sourceNode?.x ?? actionInfo.x) + H_GAP),
		y: snapCoordinate(sourceNode?.y ?? actionInfo.y),
	}
	insertAction(clonedAction, actionInfo.id, position)
	nodePositions.value[clonedAction.id] = position
	focusNode(clonedAction.id)
	configOpen.value = true
	commitUndo()
}

function deleteSelectedAction() {
	// Multi-select: delete all selected action/variable nodes
	const idsToDelete = selectedNodeIds.value.size > 1
		? [...selectedNodeIds.value].filter((id) => id !== "trigger")
		: selectedActionInfo.value ? [selectedNodeId.value!] : []

	if (idsToDelete.length > 0) {
		// Also remove variable nodes that are in the selection
		const varIds = idsToDelete.filter((id) => variableNodes.value.some((vn) => vn.id === id))
		if (varIds.length) {
			variableNodes.value = variableNodes.value.filter((vn) => !varIds.includes(vn.id))
			dataWires.value = dataWires.value.filter((w) => !varIds.includes(w.fromNode) && !varIds.includes(w.toNode))
		}
		deleteGraphNodes(idsToDelete.filter((id) => !varIds.includes(id)))
		if (varIds.length && !idsToDelete.filter((id) => !varIds.includes(id)).length) {
			clearSelection()
			commitUndo()
		}
		return
	}
}

function deleteGraphNodes(ids: string[]) {
	const graph = activeGraph.value
	if (!graph) return
	const idSet = new Set(ids)
	graph.nodes = graph.nodes.filter((n) => !idSet.has(n.id))
	graph.edges = graph.edges.filter((e) => !idSet.has(e.from) && !idSet.has(e.to))
	// Clean data wires too
	dataWires.value = dataWires.value.filter((w) => !idSet.has(w.fromNode) && !idSet.has(w.toNode))
	// Fix entry node if deleted
	if (graph.entryNodeId && idSet.has(graph.entryNodeId)) {
		graph.entryNodeId = graph.nodes[0]?.id ?? ""
	}
	clearSelection()
	commitUndo()
}

function deleteSelectedEdge() {
	const edgeId = selectedEdgeId.value
	if (!edgeId) return
	const edge = edges.value.find((e) => e.id === edgeId)
	if (!edge) return

	if (activeGraph.value) {
		deleteExecEdge(edgeId)
		selectedEdgeId.value = undefined
		return
	}
	selectedEdgeId.value = undefined
}

function canMoveSelectedAction(direction: -1 | 1) {
	return Boolean(selectedActionInfo.value && direction)
}

function moveSelectedAction(direction: -1 | 1) {
	const nodeId = selectedActionInfo.value?.id
	if (!nodeId || !canMoveSelectedAction(direction)) return
	const node = activeGraph.value?.nodes.find((graphNode) => graphNode.id === nodeId)
	if (!node) return
	node.x = snapCoordinate(node.x + direction * H_GAP)
	nodePositions.value[node.id] = { x: node.x, y: node.y }
	commitUndo()
}

function getCanvasPoint(event: DragEvent): NodePosition {
	return getCanvasPointFromClient(event.clientX, event.clientY)
}

function updateGhostNode(event: DragEvent) {
	ghostNode.value = getCanvasPoint(event)
}

function getCanvasPointFromClient(clientX: number, clientY: number): NodePosition {
	return getCanvasPointFromClientPosition(clientX, clientY)
}

// ─── Subgraph Management ──────────────────────────────────────────────────────

function addSubgraphCallNode(subgraphId: string) {
	const graph = ensureGraph()
	const canvasPoint = contextMenu.value.canvasPoint ?? { x: 100, y: 200 }
	const id = nanoid()
	graph.nodes.push({
		id,
		type: "subgraphCall",
		x: canvasPoint.x,
		y: canvasPoint.y,
		subgraphId,
		inputs: {},
	})
	if (pendingFlowConnection.value) {
		connectFlowToNode(pendingFlowConnection.value.fromNode, pendingFlowConnection.value.fromPort, id)
	} else if (!graph.entryNodeId) {
		graph.entryNodeId = id
	}
	focusedSubgraphId.value = subgraphId
	closeContextMenu()
	commitUndo()
}

function openSubgraphFromNode(nodeId: string) {
	const graphNode = activeGraph.value?.nodes.find((node) => node.id === nodeId)
	if (graphNode?.type !== "subgraphCall") return
	openSubgraphCanvas(graphNode.subgraphId)
}

async function runMainExecution() {
	activeTestExecutionId.value = await actionQueueStore.testExecution(model.value)
}

function formatNodeDuration(durationMs: number) {
	if (durationMs < 1000) return `${Math.max(1, Math.round(durationMs))}ms`
	return `${(durationMs / 1000).toFixed(durationMs < 10000 ? 1 : 0)}s`
}

function nodeTitleById(nodeId: string) {
	return nodes.value.find((node) => node.id === nodeId)?.title ?? nodeId
}

onMounted(() => {
	window.addEventListener("keydown", handleKeydown)
	window.addEventListener("keyup", handleKeyup)
	window.addEventListener("click", handleWindowClick)
})
onUnmounted(() => {
	window.removeEventListener("keydown", handleKeydown)
	window.removeEventListener("keyup", handleKeyup)
	window.removeEventListener("click", handleWindowClick)
	pausePlayheadPreview()
})
</script>

<style scoped>
.node-automation {
	background: #151515;
	color: var(--text-color);
	display: flex;
	flex: 1;
	flex-direction: column;
	min-height: 0;
}

.node-automation__toolbar {
	align-items: center;
	background: #202020;
	border-bottom: 1px solid #343434;
	display: flex;
	gap: 1rem;
	justify-content: space-between;
	padding: 0.85rem 1rem;
}

.node-automation__toolbar h2 {
	margin: 0;
}

.node-automation__eyebrow {
	color: #e9aaff;
	font-size: 0.72rem;
	font-weight: 700;
	letter-spacing: 0;
	margin: 0 0 0.2rem;
	text-transform: uppercase;
}

.node-automation__body {
	display: grid;
	flex: 1;
	grid-template-columns: minmax(0, 1fr) 320px;
	min-height: 0;
}

.node-automation__canvas {
	background-color: #202020;
	background-image: linear-gradient(#353535 1px, transparent 1px), linear-gradient(90deg, #353535 1px, transparent 1px);
	background-size: 42px 42px;
	border: 2px solid #8b35e6;
	margin: 0.75rem;
	overflow: auto;
	position: relative;
}

.node-automation__canvas.panning {
	cursor: grabbing;
}

.node-automation__canvas.space-held {
	cursor: grab;
}

.node-automation__surface {
	position: relative;
	transform-origin: 0 0;
}

.sr-only {
	border: 0;
	clip: rect(0, 0, 0, 0);
	height: 1px;
	margin: -1px;
	overflow: hidden;
	padding: 0;
	position: absolute;
	white-space: nowrap;
	width: 1px;
}
</style>
