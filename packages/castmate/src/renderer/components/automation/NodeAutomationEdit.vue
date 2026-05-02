<template>
	<div class="node-automation">
		<header class="node-automation__toolbar">
			<div>
				<p class="node-automation__eyebrow">Automation Flow</p>
				<h2>{{ model.name || "Untitled Automation" }}</h2>
			</div>
			<div class="node-automation__mode">
				<button :class="{ active: mode === 'nodes' }" type="button" @click="mode = 'nodes'">
					<i class="mdi mdi-graph-outline" />
					Nodes
				</button>
				<button :class="{ active: mode === 'timeline' }" type="button" @click="mode = 'timeline'">
					<i class="mdi mdi-timeline-clock-outline" />
					Timeline
				</button>
			</div>
		</header>

		<div v-if="mode === 'nodes'" class="node-automation__body">
			<section
				ref="canvasRef"
				class="node-automation__canvas"
				:class="{ panning: isPanning }"
				@pointerdown="handleCanvasPointerDown"
				@dragover.prevent
				@drop.prevent="dropActionOnCanvas"
				@wheel.ctrl.prevent="zoomFromWheel"
				@contextmenu.prevent="openCanvasContextMenu"
			>
				<div class="node-automation__canvas-controls">
					<button type="button" aria-label="Zoom out" @click="setZoom(zoom - ZOOM_STEP, true)" v-tooltip="'Zoom out'">
						<i class="mdi mdi-magnify-minus-outline" />
					</button>
					<span>{{ Math.round(zoom * 100) }}%</span>
					<button type="button" aria-label="Zoom in" @click="setZoom(zoom + ZOOM_STEP, true)" v-tooltip="'Zoom in'">
						<i class="mdi mdi-magnify-plus-outline" />
					</button>
					<button type="button" aria-label="Fit graph" @click="fitGraph" v-tooltip="'Fit graph'">
						<i class="mdi mdi-fit-to-screen-outline" />
					</button>
					<button type="button" aria-label="Reset view" @click="resetView" v-tooltip="'Reset view'">
						<i class="mdi mdi-backup-restore" />
					</button>
					<button
						type="button"
						:class="{ active: snapToGrid }"
						aria-label="Toggle snap to grid"
						@click="toggleSnapToGrid"
						v-tooltip="'Toggle snap to grid'"
					>
						<i class="mdi mdi-grid" />
					</button>
					<span class="node-automation__control-divider" />
					<button
						type="button"
						:aria-label="isPreviewPlaying ? 'Pause preview playhead' : 'Play preview playhead'"
						@click="togglePlayheadPreview"
						v-tooltip="isPreviewPlaying ? 'Pause preview playhead' : 'Play preview playhead'"
					>
						<i :class="isPreviewPlaying ? 'mdi mdi-pause' : 'mdi mdi-play'" />
					</button>
					<button type="button" aria-label="Reset preview playhead" @click="resetPlayheadPreview" v-tooltip="'Reset preview playhead'">
						<i class="mdi mdi-stop" />
					</button>
					<div class="node-automation__preview-status">
						<div class="node-automation__preview-meter">
							<span :style="{ width: `${playheadProgress}%` }" />
						</div>
						<strong>{{ currentPreviewStep?.node.title || "Preview idle" }}</strong>
						<small>{{ playheadElapsedLabel }} / {{ previewTotalLabel }}</small>
					</div>
				</div>

				<div
					class="node-automation__surface"
					:style="{
						width: `${canvasSize.width}px`,
						height: `${canvasSize.height}px`,
						transform: `translate(${pan.x}px, ${pan.y}px) scale(${zoom})`,
					}"
				>
					<div
						v-for="lane in lanes"
						:key="lane.id"
						class="node-automation__lane"
						:class="`node-automation__lane--${lane.kind}`"
						:style="{
							transform: `translate(${lane.x}px, ${lane.y}px)`,
							width: `${lane.width}px`,
							height: `${lane.height}px`,
						}"
					>
						<span>{{ lane.label }}</span>
					</div>

					<svg class="node-automation__edges" :viewBox="viewBox">
						<path
							v-for="edge in edges"
							:key="`${edge.id}:hit`"
							class="node-automation__edge-hit"
							:class="{ active: dropTargetEdgeId === edge.id }"
							:d="edge.path"
							vector-effect="non-scaling-stroke"
							@dragover.prevent.stop="dropTargetEdgeId = edge.id"
							@dragleave.stop="clearDropEdge(edge.id)"
							@drop.prevent.stop="dropActionOnEdge($event, edge)"
						/>
						<path
							v-for="edge in edges"
							:key="`${edge.id}:line`"
							class="node-automation__edge"
							:class="{ active: dropTargetEdgeId === edge.id }"
							:d="edge.path"
							vector-effect="non-scaling-stroke"
						/>
						<template v-for="(guide, gi) in alignmentGuides" :key="`guide-${gi}`">
							<line
								v-if="guide.axis === 'x'"
								class="node-automation__alignment-guide"
								:x1="guide.position"
								:y1="guide.from - 8"
								:x2="guide.position"
								:y2="guide.to + 8"
								vector-effect="non-scaling-stroke"
							/>
							<line
								v-else
								class="node-automation__alignment-guide"
								:x1="guide.from - 8"
								:y1="guide.position"
								:x2="guide.to + 8"
								:y2="guide.position"
								vector-effect="non-scaling-stroke"
							/>
						</template>
					</svg>

					<button
						v-for="node in nodes"
						:key="node.id"
						class="node-automation__node"
						:class="[
							`node-automation__node--${node.kind}`,
							{
								selected: selectedNodeIds.has(node.id),
								'drop-target': dropTargetNodeId === node.id,
								'preview-active': playheadNodeId === node.id,
							},
						]"
						:style="{ transform: `translate(${node.x}px, ${node.y}px)`, height: `${node.height}px` }"
						type="button"
						@pointerdown.stop="startDrag($event, node)"
						@click.stop="selectNode($event, node.id)"
						@contextmenu.prevent.stop="openNodeContext($event, node)"
						@dragover.prevent.stop="dropTargetNodeId = node.id"
						@dragleave.stop="clearDropTarget(node.id)"
						@drop.prevent.stop="dropActionOnNode($event, node)"
					>
						<span class="node-automation__handle node-automation__handle--in" />
						<span class="node-automation__node-icon">
							<i :class="node.icon" />
						</span>
						<span class="node-automation__node-text">
							<strong>{{ node.title }}</strong>
							<small>{{ node.subtitle }}</small>
						</span>
						<span v-if="node.badge" class="node-automation__node-badge">{{ node.badge }}</span>
						<dl v-if="node.configLines?.length" class="node-automation__node-config">
							<div v-for="(line, li) in node.configLines" :key="li" class="node-automation__node-config-line">
								<dt>{{ line.label }}</dt>
								<dd>{{ line.value }}</dd>
							</div>
						</dl>
						<span
							v-if="node.id !== 'trigger'"
							class="node-automation__handle node-automation__handle--out"
							title="Drop an action here to insert after this node"
						/>
					</button>

					<div
						v-if="rubberBand"
						class="node-automation__rubber-band"
						:style="{
							transform: `translate(${rubberBand.x}px, ${rubberBand.y}px)`,
							width: `${rubberBand.width}px`,
							height: `${rubberBand.height}px`,
						}"
					/>
				</div>

				<div
					v-if="contextMenu.open"
					class="node-automation__context-menu"
					:style="{ left: `${contextMenu.x}px`, top: `${contextMenu.y}px` }"
					@click.stop
					@pointerdown.stop
					@mousedown.stop
					@contextmenu.prevent.stop
				>
					<header class="node-automation__context-menu-header">
						<div>
							<strong>{{ contextMenu.nodeId ? "Node Menu" : "Canvas Menu" }}</strong>
							<span>{{ contextMenuSubtitle }}</span>
						</div>
						<button type="button" aria-label="Close menu" @click="closeContextMenu">
							<i class="mdi mdi-close" />
						</button>
					</header>
					<label class="node-automation__context-menu-search">
						<i class="mdi mdi-magnify" />
						<input v-model="contextMenuQuery" type="search" placeholder="Search triggers or actions..." />
					</label>
					<section class="node-automation__menu-section">
						<button type="button" class="node-automation__menu-section-header" :aria-expanded="isContextGroupOpen('triggers')" @click="toggleContextGroup('triggers')">
							<span><i class="mdi mdi-flash" /> Triggers</span>
							<i :class="isContextGroupOpen('triggers') ? 'mdi mdi-chevron-up' : 'mdi mdi-chevron-down'" />
						</button>
						<div v-if="isContextGroupOpen('triggers')" class="node-automation__menu-groups">
							<div v-for="group in triggerContextGroups" :key="group.id" class="node-automation__menu-group">
								<button type="button" class="node-automation__menu-group-header" :aria-expanded="isContextGroupOpen(`trigger:${group.id}`)" @click="toggleContextGroup(`trigger:${group.id}`)">
									<span>
										<i :class="group.icon" :style="{ color: group.color }" />
										{{ group.name }}
									</span>
									<i :class="isContextGroupOpen(`trigger:${group.id}`) ? 'mdi mdi-chevron-up' : 'mdi mdi-chevron-down'" />
								</button>
								<div v-if="isContextGroupOpen(`trigger:${group.id}`)" class="node-automation__menu-items">
									<button v-for="item in group.items" :key="item.key" type="button" @click="selectTriggerFromContext(item.key)">
										<i :class="item.icon" :style="{ color: item.color }" />
										<span>
											<strong>{{ item.name }}</strong>
											<small>{{ item.pluginName }}</small>
										</span>
										<em class="trigger">Trigger</em>
									</button>
								</div>
							</div>
						</div>
					</section>
					<section class="node-automation__menu-section">
						<button type="button" class="node-automation__menu-section-header" :aria-expanded="isContextGroupOpen('actions')" @click="toggleContextGroup('actions')">
							<span><i class="mdi mdi-play-circle-outline" /> Actions</span>
							<i :class="isContextGroupOpen('actions') ? 'mdi mdi-chevron-up' : 'mdi mdi-chevron-down'" />
						</button>
						<div v-if="isContextGroupOpen('actions')" class="node-automation__menu-groups">
							<div v-for="group in actionContextGroups" :key="group.id" class="node-automation__menu-group">
								<button type="button" class="node-automation__menu-group-header" :aria-expanded="isContextGroupOpen(`action:${group.id}`)" @click="toggleContextGroup(`action:${group.id}`)">
									<span>
										<i :class="group.icon" :style="{ color: group.color }" />
										{{ group.name }}
									</span>
									<i :class="isContextGroupOpen(`action:${group.id}`) ? 'mdi mdi-chevron-up' : 'mdi mdi-chevron-down'" />
								</button>
								<div v-if="isContextGroupOpen(`action:${group.id}`)" class="node-automation__menu-items">
									<button v-for="item in group.items" :key="item.key" type="button" @click="selectActionFromContext(item.key)">
										<i :class="item.icon" :style="{ color: item.color }" />
										<span>
											<strong>{{ item.name }}</strong>
											<small>{{ item.pluginName }}</small>
										</span>
										<em>Action</em>
									</button>
								</div>
							</div>
						</div>
					</section>
				</div>
			</section>

			<aside class="node-automation__details" :class="{ empty: !selectedNode }">
				<header class="node-automation__details-header">
					<div>
						<p class="node-automation__eyebrow">{{ selectedNode ? "Node Context" : "Flow Map" }}</p>
						<h3>{{ selectedNode?.title || "Select a node" }}</h3>
					</div>
					<button
						v-if="selectedNode"
						class="node-automation__icon-button"
						type="button"
						aria-label="Close context"
						@click="clearSelection()"
						v-tooltip="'Close context'"
					>
						<i class="mdi mdi-close" />
					</button>
				</header>

				<template v-if="selectedNode">
					<section class="node-automation__context-section">
						<button type="button" class="node-automation__context-header" :aria-expanded="detailsOpen" @click="detailsOpen = !detailsOpen">
							<span><i class="mdi mdi-information-outline" /> Details</span>
							<i :class="detailsOpen ? 'mdi mdi-chevron-up' : 'mdi mdi-chevron-down'" />
						</button>
						<dl v-if="detailsOpen">
							<div>
								<dt>Type</dt>
								<dd>{{ selectedNode.kind }}</dd>
							</div>
							<div>
								<dt>Source</dt>
								<dd>{{ selectedNode.subtitle }}</dd>
							</div>
							<div v-if="selectedNode.path">
								<dt>Path</dt>
								<dd>{{ selectedNode.path }}</dd>
							</div>
						</dl>
					</section>

					<data-binding-path local-path="automation">
						<section class="node-automation__context-section">
							<button type="button" class="node-automation__context-header" :aria-expanded="configOpen" @click="configOpen = !configOpen">
								<span><i class="mdi mdi-tune" /> Configure</span>
								<i :class="configOpen ? 'mdi mdi-chevron-up' : 'mdi mdi-chevron-down'" />
							</button>
							<div v-if="configOpen" class="node-automation__config">
								<action-config-edit
									v-if="selectedActionDef"
									v-model="selectedActionDef"
									:sequence="selectedSequence"
									:local-path="selectedActionPath"
								/>
								<trigger-config-edit v-else-if="selectedNode.id === 'trigger'" v-model="model" />
								<p v-else class="node-automation__hint">
									This node groups other actions. Select a child action node to edit its settings.
								</p>
							</div>
						</section>
					</data-binding-path>

					<section class="node-automation__context-section">
						<button type="button" class="node-automation__context-header" :aria-expanded="actionsOpen" @click="actionsOpen = !actionsOpen">
							<span><i class="mdi mdi-dots-horizontal-circle-outline" /> Node Actions</span>
							<i :class="actionsOpen ? 'mdi mdi-chevron-up' : 'mdi mdi-chevron-down'" />
						</button>
						<div v-if="actionsOpen" class="node-automation__quick-actions">
							<div class="node-automation__action-picker">
								<label>
									<span>Add Action</span>
									<input v-model="actionPaletteQuery" type="search" placeholder="Search plugin or action..." />
									<select v-model="selectedActionToAdd">
										<option value="">Choose an action...</option>
										<optgroup v-for="plugin in actionPalette" :key="plugin.id" :label="plugin.name">
											<option v-for="action in plugin.actions" :key="action.key" :value="action.key">
												{{ action.name }}
											</option>
										</optgroup>
									</select>
								</label>
								<button type="button" :disabled="!selectedActionToAdd" @click="addActionFromPalette">
									<i class="mdi mdi-plus" />
									Insert After Selection
								</button>
								<div class="node-automation__palette-list">
									<button
										v-for="action in flatActionPalette"
										:key="action.key"
										type="button"
										draggable="true"
										@click="selectedActionToAdd = action.key"
										@dragstart="startActionPaletteDrag($event, action.key)"
									>
										<i class="mdi mdi-drag" />
										<span>{{ action.pluginName }}</span>
										<strong>{{ action.name }}</strong>
									</button>
								</div>
							</div>
							<div class="node-automation__action-grid">
								<button type="button" :disabled="!canEditSelectedAction" @click="duplicateSelectedAction">
									<i class="mdi mdi-content-duplicate" />
									Duplicate
								</button>
								<button type="button" :disabled="!canMoveSelectedAction(-1)" @click="moveSelectedAction(-1)">
									<i class="mdi mdi-arrow-left" />
									Move Left
								</button>
								<button type="button" :disabled="!canMoveSelectedAction(1)" @click="moveSelectedAction(1)">
									<i class="mdi mdi-arrow-right" />
									Move Right
								</button>
								<button type="button" class="danger" :disabled="!canEditSelectedAction" @click="deleteSelectedAction">
									<i class="mdi mdi-trash-can-outline" />
									Delete
								</button>
							</div>
							<button type="button" @click="mode = 'timeline'">
								<i class="mdi mdi-timeline-clock-outline" />
								Open in Timeline
							</button>
							<button type="button" @click="resetSelectedNodePosition">
								<i class="mdi mdi-crosshairs-gps" />
								Reset Visual Position
							</button>
						</div>
					</section>
				</template>
				<p v-else class="node-automation__hint">
					Left click selects a node. Right click opens the collapsible context panel with the same configuration
					controls as Timeline.
				</p>

				<section class="node-automation__context-section">
					<button type="button" class="node-automation__context-header" :aria-expanded="activityOpen" @click="activityOpen = !activityOpen">
						<span><i class="mdi mdi-history" /> Node Activity</span>
						<i :class="activityOpen ? 'mdi mdi-chevron-up' : 'mdi mdi-chevron-down'" />
					</button>
					<ol v-if="activityOpen" class="node-automation__activity">
						<li v-for="entry in activityLog" :key="entry.id">
							<strong>{{ entry.title }}</strong>
							<span>{{ entry.detail }}</span>
						</li>
					</ol>
				</section>
			</aside>
		</div>

		<data-binding-path v-else local-path="automation">
			<automation-edit v-model="model" v-model:view="view" class="node-automation__classic" />
		</data-binding-path>
	</div>
</template>

<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, useModel } from "vue"
import {
	ActionSelection,
	AutomationConfig,
	AutomationResourceView,
	AutomationEdit,
	ActionConfigEdit,
	DataBindingPath,
	TriggerConfigEdit,
	useCommitUndo,
	usePluginStore,
	ActionDefinition,
} from "castmate-ui-core"
import {
	ActionStack,
	AnyAction,
	FloatingSequence,
	Sequence,
	assignNewIds,
	findActionAndSequenceById,
	isActionStack,
	isFlowAction,
	isTimeAction,
	isObjectSchema,
	constructDefault,
} from "castmate-schema"
import { useNodeActivity } from "./useNodeActivity"
import { useNodeCanvas, type NodeEditorViewState, type NodePosition } from "./useNodeCanvas"
import { useNodeContextMenu } from "./useNodeContextMenu"
import { useNodeDrag } from "./useNodeDrag"
import { useAutomationPreview } from "./useAutomationPreview"

interface ConfigLine {
	label: string
	value: string
}

interface NodeData extends NodePosition {
	id: string
	kind: "trigger" | "action" | "stack" | "time" | "flow" | "floating"
	title: string
	subtitle: string
	icon: string
	badge?: string
	path?: string
	configLines?: ConfigLine[]
	height: number
}

interface EdgeData {
	id: string
	from: string
	to: string
	path: string
}

interface LaneData extends NodePosition {
	id: string
	kind: "main" | "floating" | "stack" | "time" | "flow"
	label: string
	width: number
	height: number
}

const props = defineProps<{
	modelValue: AutomationConfig
	view: AutomationResourceView & { nodePositions?: Record<string, NodePosition>; nodeView?: NodeEditorViewState }
}>()

const model = useModel(props, "modelValue")
const view = useModel(props, "view")
const mode = ref<"nodes" | "timeline">("nodes")
const selectedNodeId = ref<string>()
const selectedNodeIds = ref<Set<string>>(new Set())
const selectedActionToAdd = ref("")
const actionPaletteQuery = ref("")
const dropTargetNodeId = ref<string>()
const dropTargetEdgeId = ref<string>()
const rubberBand = ref<{ x: number; y: number; width: number; height: number } | null>(null)
const detailsOpen = ref(true)
const configOpen = ref(true)
const actionsOpen = ref(false)
const activityOpen = ref(true)
const { activityLog, logActivity } = useNodeActivity()
const pluginStore = usePluginStore()
const commitUndo = useCommitUndo()

const NODE_WIDTH = 220
const NODE_BASE_HEIGHT = 74
const CONFIG_LINE_HEIGHT = 20
const MAX_CONFIG_LINES = 4
const H_GAP = 285
const V_GAP = 128

function computeNodeHeight(configLines?: ConfigLine[]): number {
	if (!configLines || configLines.length === 0) return NODE_BASE_HEIGHT
	return NODE_BASE_HEIGHT + configLines.length * CONFIG_LINE_HEIGHT + 4
}

const nodePositions = computed(() => {
	view.value.nodePositions ??= {}
	return view.value.nodePositions
})

const graph = computed(() => buildGraph(model.value, pluginStore.pluginMap))
const nodes = computed(() =>
	graph.value.nodes.map((node) => ({
		...node,
		...(nodePositions.value[node.id] ?? { x: node.x, y: node.y }),
	}))
)
const edges = computed<EdgeData[]>(() => {
	const byId = new Map(nodes.value.map((node) => [node.id, node]))
	return graph.value.edges.flatMap((edge) => {
		const from = byId.get(edge.from)
		const to = byId.get(edge.to)
		if (!from || !to) return []
		const startX = from.x + NODE_WIDTH
		const startY = from.y + from.height / 2
		const endX = to.x
		const endY = to.y + to.height / 2
		const midX = startX + Math.max(60, (endX - startX) / 2)
		return [
			{
				...edge,
				path: `M ${startX} ${startY} C ${midX} ${startY}, ${midX} ${endY}, ${endX} ${endY}`,
			},
		]
	})
})
const lanes = computed<LaneData[]>(() => {
	const groups = new Map<string, { kind: LaneData["kind"]; label: string; nodes: NodeData[] }>()
	for (const node of nodes.value) {
		const lane = getNodeLane(node)
		const group = groups.get(lane.id)
		if (group) {
			group.nodes.push(node)
		} else {
			groups.set(lane.id, { kind: lane.kind, label: lane.label, nodes: [node] })
		}
	}

	return [...groups.entries()].map(([id, group]) => {
		const minX = Math.min(...group.nodes.map((node) => node.x))
		const minY = Math.min(...group.nodes.map((node) => node.y))
		const maxX = Math.max(...group.nodes.map((node) => node.x + NODE_WIDTH))
		const maxY = Math.max(...group.nodes.map((node) => node.y + node.height))
		return {
			id,
			kind: group.kind,
			label: group.label,
			x: Math.max(12, minX - 18),
			y: Math.max(12, minY - 34),
			width: Math.max(NODE_WIDTH + 36, maxX - minX + 36),
			height: Math.max(NODE_BASE_HEIGHT + 58, maxY - minY + 58),
		}
	})
})
const selectedNode = computed(() => nodes.value.find((node) => node.id === selectedNodeId.value))
const previewNodes = computed(() => nodes.value.filter((node) => node.id !== "trigger").sort((a, b) => a.x - b.x || a.y - b.y))
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
	return findActionAndSequenceById(selectedNodeId.value, model.value)
})
const selectedActionPath = computed(() => selectedActionInfo.value?.path)
const selectedSequence = computed(() => {
	const actionInfo = selectedActionInfo.value
	if (!actionInfo || isActionStack(actionInfo.action)) return undefined
	return actionInfo.sequence
})
const selectedActionDef = computed(() => {
	const actionInfo = selectedActionInfo.value
	if (!actionInfo || isActionStack(actionInfo.action)) return undefined
	return actionInfo.action
})
const selectedActionPosition = computed(() => {
	if (!selectedActionPath.value) return undefined
	return getPathPosition(selectedActionPath.value)
})
const canEditSelectedAction = computed(() => {
	const position = selectedActionPosition.value
	return Boolean(position && selectedActionInfo.value)
})
const actionPalette = computed(() =>
	[...pluginStore.pluginMap.values()]
		.map((plugin) => ({
			id: plugin.id,
			name: plugin.name,
			actions: Object.values(plugin.actions)
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
	width: Math.max(1280, ...nodes.value.map((node) => node.x + NODE_WIDTH + 160)),
	height: Math.max(720, ...nodes.value.map((node) => node.y + node.height + 160)),
}))
const graphBounds = computed(() => {
	const minX = Math.min(42, ...nodes.value.map((node) => node.x))
	const minY = Math.min(88, ...nodes.value.map((node) => node.y))
	const maxX = Math.max(...nodes.value.map((node) => node.x + NODE_WIDTH))
	const maxY = Math.max(...nodes.value.map((node) => node.y + node.height))
	return { minX, minY, width: maxX - minX, height: maxY - minY }
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
	fitGraph,
	resetView,
	startPan,
	getCanvasPointFromClient: getCanvasPointFromClientPosition,
} = useNodeCanvas(view, graphBounds, commitUndo)
const {
	contextMenu,
	contextMenuQuery,
	contextMenuSubtitle,
	actionContextGroups,
	triggerContextGroups,
	openContextMenu,
	closeContextMenu,
	toggleContextGroup,
	isContextGroupOpen,
} = useNodeContextMenu(nodes, pluginStore, getCanvasPointFromClient, getNodeLane)
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

function summarizeConfigValue(value: unknown): string {
	if (value == null) return "—"
	if (typeof value === "string") return value.length > 28 ? value.slice(0, 25) + "…" : value || "—"
	if (typeof value === "number" || typeof value === "boolean") return String(value)
	if (Array.isArray(value)) return `[${value.length} item${value.length === 1 ? "" : "s"}]`
	if (typeof value === "object") {
		const keys = Object.keys(value)
		if (keys.length === 0) return "{}"
		return `{${keys.slice(0, 2).join(", ")}${keys.length > 2 ? "…" : ""}}`
	}
	return String(value)
}

function extractConfigSummary(
	action: AnyAction,
	pluginMap: Map<string, { actions: Record<string, ActionDefinition> }>
): ConfigLine[] {
	const actionDef = pluginMap.get(action.plugin)?.actions?.[action.action]
	if (!actionDef) return []

	const lines: ConfigLine[] = []
	const schema = actionDef.config
	if (schema && isObjectSchema(schema) && action.config) {
		for (const [key, propSchema] of Object.entries(schema.properties)) {
			if (lines.length >= MAX_CONFIG_LINES) break
			const value = (action.config as Record<string, unknown>)[key]
			if (value == null && !propSchema.required) continue
			const label = ("name" in propSchema && propSchema.name) ? String(propSchema.name) : titleCase(key)
			lines.push({ label, value: summarizeConfigValue(value) })
		}
	}

	if (isFlowAction(action) && actionDef.type === "flow") {
		const flowDef = actionDef as { flowConfig?: { type: ObjectConstructor; properties: Record<string, { name?: string }> } }
		action.subFlows.forEach((flow, i) => {
			if (lines.length >= MAX_CONFIG_LINES) return
			let branchLabel = `Branch ${i + 1}`
			if (flowDef.flowConfig && isObjectSchema(flowDef.flowConfig) && flow.config) {
				const firstProp = Object.entries(flowDef.flowConfig.properties)[0]
				if (firstProp) {
					const val = (flow.config as Record<string, unknown>)[firstProp[0]]
					if (val != null) branchLabel += `: ${summarizeConfigValue(val)}`
				}
			}
			lines.push({ label: "↳", value: branchLabel })
		})
	}

	if (isTimeAction(action)) {
		action.offsets.forEach((offset, i) => {
			if (lines.length >= MAX_CONFIG_LINES) return
			lines.push({ label: "↳", value: `+${offset.offset}s → ${offset.actions.length} action${offset.actions.length === 1 ? "" : "s"}` })
		})
	}

	return lines
}

function buildGraph(automation: AutomationConfig, pluginMap: Map<string, { actions: Record<string, ActionDefinition> }>) {
	const nodes: NodeData[] = []
	const edges: Omit<EdgeData, "path">[] = []

	const triggerId = "trigger"
	nodes.push({
		id: triggerId,
		kind: "trigger",
		title: automation.trigger ? titleCase(automation.trigger) : "Manual Start",
		subtitle: automation.plugin ? `${automation.plugin} trigger` : "No trigger configured",
		icon: "mdi mdi-flash",
		x: 42,
		y: 88,
		height: NODE_BASE_HEIGHT,
	})

	const mainNodes = addSequence(nodes, edges, automation.sequence, "sequence", 1, 0, "Main", pluginMap)
	if (mainNodes[0]) edges.push({ id: `${triggerId}:${mainNodes[0]}`, from: triggerId, to: mainNodes[0] })

	automation.floatingSequences?.forEach((sequence, index) => {
		const floatingId = sequence.id || `floating-${index}`
		nodes.push({
			id: floatingId,
			kind: "floating",
			title: `Floating ${index + 1}`,
			subtitle: `${sequence.actions.length} action${sequence.actions.length === 1 ? "" : "s"}`,
			icon: "mdi mdi-vector-polyline",
			badge: "free",
			x: 42,
			y: 280 + index * V_GAP,
			path: `floatingSequences[${index}]`,
			height: NODE_BASE_HEIGHT,
		})
		const childNodes = addSequence(nodes, edges, sequence, `floatingSequences[${index}]`, 1, index + 2, `Floating ${index + 1}`, pluginMap)
		if (childNodes[0]) edges.push({ id: `${floatingId}:${childNodes[0]}`, from: floatingId, to: childNodes[0] })
	})

	return { nodes, edges }
}

function addSequence(
	nodes: NodeData[],
	edges: Omit<EdgeData, "path">[],
	sequence: Sequence | FloatingSequence,
	path: string,
	column: number,
	row: number,
	group: string,
	pluginMap: Map<string, { actions: Record<string, ActionDefinition> }>
) {
	const ids: string[] = []
	sequence.actions.forEach((action, index) => {
		const node = createNode(action, `${path}.actions[${index}]`, column + index, row, group, pluginMap)
		nodes.push(node)
		ids.push(node.id)

		if (index > 0) {
			edges.push({ id: `${ids[index - 1]}:${node.id}`, from: ids[index - 1], to: node.id })
		}

		if (isActionStack(action)) {
			action.stack.forEach((stackAction, stackIndex) => {
				const child = createNode(stackAction, `${node.path}.stack[${stackIndex}]`, column + index, row + stackIndex + 1, "Stack", pluginMap)
				nodes.push(child)
				edges.push({ id: `${node.id}:${child.id}`, from: node.id, to: child.id })
			})
		}

		if (isTimeAction(action)) {
			action.offsets.forEach((offset, offsetIndex) => {
				const children = addSequence(
					nodes,
					edges,
					offset,
					`${node.path}.offsets[${offsetIndex}]`,
					column + index + 1,
					row + offsetIndex + 1,
					`+${offset.offset}s`,
					pluginMap
				)
				if (children[0]) edges.push({ id: `${node.id}:${children[0]}`, from: node.id, to: children[0] })
			})
		}

		if (isFlowAction(action)) {
			action.subFlows.forEach((flow, flowIndex) => {
				const children = addSequence(
					nodes,
					edges,
					flow,
					`${node.path}.subFlows[${flowIndex}]`,
					column + index + 1,
					row + flowIndex + 1,
					`Flow ${flowIndex + 1}`,
					pluginMap
				)
				if (children[0]) edges.push({ id: `${node.id}:${children[0]}`, from: node.id, to: children[0] })
			})
		}
	})
	return ids
}

function createNode(
	action: AnyAction | ActionStack,
	path: string,
	column: number,
	row: number,
	group: string,
	pluginMap: Map<string, { actions: Record<string, ActionDefinition> }>
): NodeData {
	if (isActionStack(action)) {
		const stackCount = action.stack.length
		return {
			id: action.id,
			kind: "stack",
			title: "Action Stack",
			subtitle: `${stackCount} parallel action${stackCount === 1 ? "" : "s"}`,
			icon: "mdi mdi-layers-triple",
			badge: `${group} stack`,
			x: 42 + column * H_GAP,
			y: 88 + row * V_GAP,
			path,
			height: NODE_BASE_HEIGHT,
		}
	}

	const timingSummary = getTimingSummary(action)
	const flowSummary = getFlowSummary(action)
	const configLines = extractConfigSummary(action, pluginMap)

	return {
		id: action.id,
		kind: isFlowAction(action) ? "flow" : isTimeAction(action) ? "time" : "action",
		title: titleCase(action.action),
		subtitle: [action.plugin, action.action, timingSummary, flowSummary].filter(Boolean).join(" / "),
		icon: isFlowAction(action) ? "mdi mdi-source-branch" : isTimeAction(action) ? "mdi mdi-timer-outline" : "mdi mdi-play",
		badge: getNodeBadge(action, group),
		x: 42 + column * H_GAP,
		y: 88 + row * V_GAP,
		path,
		configLines,
		height: computeNodeHeight(configLines),
	}
}

function getNodeBadge(action: AnyAction, group: string) {
	if (isTimeAction(action)) return `${group} time`
	if (isFlowAction(action)) return `${group} flow`
	return group
}

function getTimingSummary(action: AnyAction) {
	if (!isTimeAction(action)) return undefined
	const offsets = action.offsets.length
	const duration = getConfiguredDuration(action)
	const parts = [`${offsets} offset${offsets === 1 ? "" : "s"}`]
	if (duration) parts.unshift(duration)
	return parts.join(", ")
}

function getFlowSummary(action: AnyAction) {
	if (!isFlowAction(action)) return undefined
	const branches = action.subFlows.length
	return `${branches} branch${branches === 1 ? "" : "es"}`
}

function getConfiguredDuration(action: AnyAction) {
	const duration = getPreviewConfiguredDurationSeconds(action.id)
	return duration ? formatSeconds(duration) : undefined
}

function formatSeconds(value: number) {
	return `${Number(value.toFixed(2))}s`
}

function titleCase(value: string) {
	return value
		.replace(/[-_]/g, " ")
		.replace(/([a-z])([A-Z])/g, "$1 $2")
		.replace(/\b\w/g, (letter) => letter.toUpperCase())
}

function getNodeLane(node: NodeData): Pick<LaneData, "id" | "kind" | "label"> {
	if (node.id === "trigger") return { id: "main", kind: "main", label: "Main Flow" }
	if (node.path?.includes(".stack[")) return { id: "stack", kind: "stack", label: "Stacked Actions" }
	if (node.path?.includes(".offsets[")) return { id: "time", kind: "time", label: "Time Offsets" }
	if (node.path?.includes(".subFlows[")) return { id: "flow", kind: "flow", label: "Flow Branches" }
	if (node.path?.startsWith("floatingSequences")) return { id: "floating", kind: "floating", label: "Floating Sequences" }
	return { id: "main", kind: "main", label: "Main Flow" }
}

function selectNode(event: MouseEvent | PointerEvent, nodeId: string) {
	if (event.ctrlKey || event.metaKey) {
		const next = new Set(selectedNodeIds.value)
		if (next.has(nodeId)) {
			next.delete(nodeId)
			selectedNodeId.value = next.size > 0 ? [...next][next.size - 1] : undefined
		} else {
			next.add(nodeId)
			selectedNodeId.value = nodeId
		}
		selectedNodeIds.value = next
	} else {
		focusNode(nodeId)
	}
}

function focusNode(nodeId: string) {
	selectedNodeId.value = nodeId
	selectedNodeIds.value = new Set([nodeId])
}

function clearSelection() {
	selectedNodeId.value = undefined
	selectedNodeIds.value = new Set()
}

function openNodeContext(event: MouseEvent, node: NodeData) {
	selectNode(event, node.id)
	detailsOpen.value = true
	configOpen.value = true
	actionsOpen.value = false
	openContextMenu(event, node.id)
}

function openCanvasContextMenu(event: MouseEvent) {
	const target = event.target as HTMLElement
	if (target.closest(".node-automation__canvas-controls") || target.closest(".node-automation__context-menu")) return
	const nodeElement = target.closest(".node-automation__node")
	if (nodeElement) return
	clearSelection()
	openContextMenu(event)
}

function handleCanvasPointerDown(event: PointerEvent) {
	const target = event.target as HTMLElement
	if (target.closest(".node-automation__context-menu")) return
	if (contextMenu.value.open) closeContextMenu()
	if (target.closest(".node-automation__canvas-controls")) return

	const isCanvasTarget =
		target.classList.contains("node-automation__canvas") ||
		target.classList.contains("node-automation__surface") ||
		target.classList.contains("node-automation__edges")

	if (isCanvasTarget) clearSelection()
	if (event.button === 1 && isCanvasTarget) {
		event.preventDefault()
		startPan(event)
	}
	if (event.button === 0 && isCanvasTarget) {
		startRubberBand(event)
	}
}

function startRubberBand(event: PointerEvent) {
	const canvas = canvasRef.value
	if (!canvas) return

	const origin = getCanvasPointFromClientPosition(event.clientX, event.clientY)
	const startX = event.clientX
	const startY = event.clientY
	let didMove = false

	canvas.setPointerCapture(event.pointerId)

	function onMove(moveEvent: PointerEvent) {
		const dx = Math.abs(moveEvent.clientX - startX)
		const dy = Math.abs(moveEvent.clientY - startY)
		if (!didMove && dx < 4 && dy < 4) return
		didMove = true

		const current = getCanvasPointFromClientPosition(moveEvent.clientX, moveEvent.clientY)
		const x = Math.min(origin.x, current.x)
		const y = Math.min(origin.y, current.y)
		const width = Math.abs(current.x - origin.x)
		const height = Math.abs(current.y - origin.y)
		rubberBand.value = { x, y, width, height }

		// Select nodes within the rectangle
		const ids = new Set<string>()
		for (const node of nodes.value) {
			const nodeRight = node.x + NODE_WIDTH
			const nodeBottom = node.y + node.height
			if (node.x < x + width && nodeRight > x && node.y < y + height && nodeBottom > y) {
				ids.add(node.id)
			}
		}
		selectedNodeIds.value = ids
		selectedNodeId.value = ids.size > 0 ? [...ids][0] : undefined
	}

	function onUp(upEvent: PointerEvent) {
		canvas.releasePointerCapture(upEvent.pointerId)
		canvas.removeEventListener("pointermove", onMove)
		canvas.removeEventListener("pointerup", onUp)
		canvas.removeEventListener("pointercancel", onUp)
		rubberBand.value = null
	}

	canvas.addEventListener("pointermove", onMove)
	canvas.addEventListener("pointerup", onUp)
	canvas.addEventListener("pointercancel", onUp)
}

function handleKeydown(event: KeyboardEvent) {
	if (mode.value !== "nodes") return
	const target = event.target as HTMLElement | null
	if (target?.closest("input, textarea, select, [contenteditable='true']")) return

	if (event.key === "Escape" && contextMenu.value.open) {
		event.preventDefault()
		closeContextMenu()
		return
	}

	if ((event.key === "Delete" || event.key === "Backspace") && canEditSelectedAction.value) {
		event.preventDefault()
		deleteSelectedAction()
	}

	if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "d" && canEditSelectedAction.value) {
		event.preventDefault()
		duplicateSelectedAction()
	}

	if (event.key.toLowerCase() === "f") {
		event.preventDefault()
		fitGraph()
	}
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

async function addActionFromPalette() {
	const selection = parseActionSelection(selectedActionToAdd.value)
	if (!selection) return

	const action = await pluginStore.createAction(selection)
	if (!action) return

	insertAction(action)
	logActivity("Added action", `${selection.plugin}/${selection.action}`)

	focusNode(action.id)
	configOpen.value = true
	commitUndo()
}

async function selectActionFromContext(actionKey: string) {
	const selection = parseActionSelection(actionKey)
	if (!selection) return

	const action = await pluginStore.createAction(selection)
	if (!action) return

	insertAction(action, contextMenu.value.nodeId)
	if (!contextMenu.value.nodeId && contextMenu.value.canvasPoint) {
		nodePositions.value[action.id] = contextMenu.value.canvasPoint
	}
	logActivity("Added action", `${selection.plugin}/${selection.action}`)
	focusNode(action.id)
	configOpen.value = true
	closeContextMenu()
	commitUndo()
}

async function selectTriggerFromContext(triggerKey: string) {
	const [pluginId, triggerId] = triggerKey.split(":")
	const trigger = pluginStore.pluginMap.get(pluginId)?.triggers?.[triggerId]
	if (!pluginId || !triggerId || !trigger) return

	const nextConfig = await constructDefault(trigger.config)
	const contextSchema = typeof trigger.context === "function" ? await trigger.context(nextConfig) : trigger.context

	Object.assign(model.value, {
		plugin: pluginId,
		trigger: triggerId,
		config: nextConfig,
		stop: model.value.stop ?? false,
		testContext: contextSchema ? await constructDefault(contextSchema) : model.value.testContext,
	})

	focusNode("trigger")
	configOpen.value = true
	closeContextMenu()
	logActivity("Changed trigger", `${pluginId}/${triggerId}`)
	commitUndo()
}

function startActionPaletteDrag(event: DragEvent, actionKey: string) {
	event.dataTransfer?.setData("application/showrunner-action", actionKey)
	event.dataTransfer?.setData("text/plain", actionKey)
	if (event.dataTransfer) event.dataTransfer.effectAllowed = "copy"
}

async function dropActionOnCanvas(event: DragEvent) {
	const action = await createDraggedAction(event)
	if (!action) return

	model.value.sequence.actions.push(action)
	nodePositions.value[action.id] = getCanvasPoint(event)
	logActivity("Dropped action", `${action.plugin}/${action.action} on canvas`)
	focusNode(action.id)
	configOpen.value = true
	dropTargetNodeId.value = undefined
	commitUndo()
}

async function dropActionOnNode(event: DragEvent, node: NodeData) {
	const action = await createDraggedAction(event)
	if (!action) return

	insertAction(action, node.id)
	nodePositions.value[action.id] = {
		x: snapCoordinate(node.x + H_GAP),
		y: snapCoordinate(node.y),
	}
	logActivity("Inserted action", `${action.plugin}/${action.action} after ${node.title}`)
	focusNode(action.id)
	configOpen.value = true
	dropTargetNodeId.value = undefined
	commitUndo()
}

async function dropActionOnEdge(event: DragEvent, edge: EdgeData) {
	const action = await createDraggedAction(event)
	if (!action) return

	if (edge.from === "trigger") {
		model.value.sequence.actions.unshift(action)
	} else {
		insertAction(action, edge.from)
	}

	const fromNode = nodes.value.find((node) => node.id === edge.from)
	const toNode = nodes.value.find((node) => node.id === edge.to)
	nodePositions.value[action.id] = {
		x: snapCoordinate(((fromNode?.x ?? 42) + (toNode?.x ?? 42)) / 2),
		y: snapCoordinate(((fromNode?.y ?? 88) + (toNode?.y ?? 88)) / 2),
	}
	logActivity("Inserted on edge", `${action.plugin}/${action.action}`)
	focusNode(action.id)
	configOpen.value = true
	dropTargetEdgeId.value = undefined
	commitUndo()
}

function clearDropTarget(nodeId: string) {
	if (dropTargetNodeId.value === nodeId) dropTargetNodeId.value = undefined
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

function insertAction(action: AnyAction, afterNodeId = selectedNodeId.value) {
	if (afterNodeId) {
		const position = getNodePosition(afterNodeId)
		if (position?.containerKind === "actions") {
			position.items.splice(position.index + 1, 0, action)
			return
		}
	}

	model.value.sequence.actions.push(action)
}

function duplicateSelectedAction() {
	const actionInfo = selectedActionInfo.value
	const position = selectedActionPosition.value
	if (!actionInfo || !position) return

	const clonedAction = cloneActionForNodeEditor(actionInfo.action)
	position.items.splice(position.index + 1, 0, clonedAction)
	logActivity("Duplicated node", selectedNode.value?.title || actionInfo.action.id)
	focusNode(clonedAction.id)
	configOpen.value = true
	commitUndo()
}

function deleteSelectedAction() {
	const position = selectedActionPosition.value
	if (!position) return
	const removed = position.items.splice(position.index, 1)
	if (removed.length) {
		delete nodePositions.value[removed[0].id]
		logActivity("Deleted node", selectedNode.value?.title || removed[0].id)
	}
	selectedNodeId.value = undefined
	selectedNodeIds.value = new Set()
	if (removed.length) commitUndo()
}

function canMoveSelectedAction(direction: -1 | 1) {
	const position = selectedActionPosition.value
	if (!position) return false
	const nextIndex = position.index + direction
	return nextIndex >= 0 && nextIndex < position.items.length
}

function moveSelectedAction(direction: -1 | 1) {
	const position = selectedActionPosition.value
	if (!position || !canMoveSelectedAction(direction)) return
	const [action] = position.items.splice(position.index, 1)
	position.items.splice(position.index + direction, 0, action)
	logActivity(direction < 0 ? "Moved node left" : "Moved node right", selectedNode.value?.title || action.id)
	commitUndo()
}

function getNodePosition(nodeId: string) {
	const info = findActionAndSequenceById(nodeId, model.value)
	if (!info) return undefined
	return getPathPosition(info.path)
}

function getCanvasPoint(event: DragEvent): NodePosition {
	return getCanvasPointFromClient(event.clientX, event.clientY)
}

function getCanvasPointFromClient(clientX: number, clientY: number): NodePosition {
	return getCanvasPointFromClientPosition(clientX, clientY)
}

function cloneActionForNodeEditor(action: AnyAction | ActionStack) {
	const clonedSequence = { actions: [structuredClone(action)] }
	assignNewIds(clonedSequence)
	return clonedSequence.actions[0]
}

function getPathPosition(path: string):
	| {
			items: Array<AnyAction | ActionStack>
			index: number
			containerKind: "actions" | "stack"
	  }
	| undefined {
	const parts = Array.from(path.matchAll(/([a-zA-Z]+)(?:\[(\d+)\])?/g)).map((match) => ({
		key: match[1],
		index: match[2] === undefined ? undefined : Number(match[2]),
	}))

	let cursor: any = model.value
	let lastContainer: Array<AnyAction | ActionStack> | undefined
	let lastContainerKind: "actions" | "stack" | undefined
	let lastIndex = -1

	for (const part of parts) {
		if (part.key === "actions" || part.key === "stack") {
			lastContainer = cursor?.[part.key]
			lastContainerKind = part.key
			lastIndex = part.index ?? -1
			cursor = lastContainer?.[lastIndex]
			continue
		}

		if (part.key === "sequence") {
			cursor = model.value.sequence
			continue
		}

		if (part.key === "floatingSequences") {
			cursor = model.value.floatingSequences?.[part.index ?? -1]
			continue
		}

		if (part.key === "offsets" || part.key === "subFlows") {
			cursor = cursor?.[part.key]?.[part.index ?? -1]
		}
	}

	if (!lastContainer || lastIndex < 0 || lastIndex >= lastContainer.length || !lastContainerKind) return undefined
	return { items: lastContainer, index: lastIndex, containerKind: lastContainerKind }
}

onMounted(() => {
	window.addEventListener("keydown", handleKeydown)
	window.addEventListener("click", handleWindowClick)
})
onUnmounted(() => {
	window.removeEventListener("keydown", handleKeydown)
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

.node-automation__toolbar h2,
.node-automation__details h3 {
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

.node-automation__mode {
	background: #101010;
	border: 1px solid #3f3f3f;
	border-radius: 6px;
	display: flex;
	padding: 0.2rem;
}

.node-automation__mode button {
	align-items: center;
	background: transparent;
	border: 0;
	border-radius: 4px;
	color: var(--text-color);
	cursor: pointer;
	display: flex;
	gap: 0.35rem;
	padding: 0.55rem 0.8rem;
}

.node-automation__mode button.active {
	background: #8b35e6;
	color: white;
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

.node-automation__canvas-controls {
	align-items: center;
	background: rgb(15 15 15 / 0.88);
	border: 1px solid #454545;
	border-radius: 6px;
	display: flex;
	gap: 0.35rem;
	left: 0.75rem;
	padding: 0.35rem;
	position: sticky;
	top: 0.75rem;
	width: max-content;
	z-index: 4;
}

.node-automation__canvas-controls button {
	align-items: center;
	background: #2b173d;
	border: 1px solid #7041a6;
	border-radius: 4px;
	color: var(--text-color);
	cursor: pointer;
	display: flex;
	height: 2rem;
	justify-content: center;
	width: 2rem;
}

.node-automation__canvas-controls button.active {
	background: #8b35e6;
	border-color: #e9aaff;
}

.node-automation__canvas-controls span {
	color: #e9e9e9;
	font-size: 0.8rem;
	min-width: 3rem;
	text-align: center;
}

.node-automation__canvas-controls .node-automation__control-divider {
	background: #454545;
	display: block;
	height: 1.35rem;
	min-width: 1px;
	width: 1px;
}

.node-automation__preview-status {
	align-items: center;
	background: rgb(0 0 0 / 0.28);
	border: 1px solid rgb(255 255 255 / 0.12);
	border-radius: 4px;
	display: grid;
	gap: 0.15rem;
	grid-template-columns: 8rem minmax(6rem, 1fr) auto;
	min-width: 20rem;
	padding: 0.35rem 0.5rem;
}

.node-automation__preview-status strong,
.node-automation__preview-status small {
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.node-automation__preview-status strong {
	font-size: 0.76rem;
}

.node-automation__preview-status small {
	color: #d6d6d6;
	font-size: 0.7rem;
	justify-self: end;
}

.node-automation__preview-meter {
	background: #101010;
	border: 1px solid rgb(255 255 255 / 0.12);
	border-radius: 999px;
	height: 0.42rem;
	overflow: hidden;
}

.node-automation__preview-meter span {
	background: linear-gradient(90deg, #e9aaff, #2ed47a);
	display: block;
	height: 100%;
	min-width: 0;
	transition: width 90ms linear;
}

.node-automation__surface {
	position: relative;
	transform-origin: 0 0;
}

.node-automation__edges {
	inset: 0;
	min-height: 100%;
	min-width: 100%;
	position: absolute;
	z-index: 1;
}

.node-automation__lane {
	background: rgb(255 255 255 / 0.035);
	border: 1px solid rgb(255 255 255 / 0.1);
	border-radius: 8px;
	position: absolute;
	z-index: 0;
}

.node-automation__rubber-band {
	background: rgb(139 53 230 / 0.12);
	border: 1.5px dashed #e9aaff;
	border-radius: 3px;
	pointer-events: none;
	position: absolute;
	z-index: 5;
}

.node-automation__lane span {
	background: rgb(16 16 16 / 0.86);
	border: 1px solid rgb(255 255 255 / 0.12);
	border-radius: 999px;
	color: #e9e9e9;
	font-size: 0.72rem;
	font-weight: 700;
	left: 0.75rem;
	letter-spacing: 0;
	padding: 0.2rem 0.5rem;
	position: absolute;
	top: 0.45rem;
}

.node-automation__lane--main {
	border-color: rgb(233 170 255 / 0.3);
}

.node-automation__lane--floating {
	border-color: rgb(255 155 215 / 0.35);
}

.node-automation__lane--stack {
	border-color: rgb(255 223 107 / 0.35);
}

.node-automation__lane--time {
	border-color: rgb(104 211 145 / 0.35);
}

.node-automation__lane--flow {
	border-color: rgb(100 181 246 / 0.35);
}

.node-automation__edge {
	fill: none;
	stroke: #e9aaff;
	stroke-linecap: round;
	stroke-width: 2.5px;
}

.node-automation__edge.active {
	stroke: #2ed47a;
	stroke-width: 4px;
}

.node-automation__edge-hit {
	fill: none;
	pointer-events: stroke;
	stroke: transparent;
	stroke-linecap: round;
	stroke-width: 22px;
}

.node-automation__edge-hit.active {
	stroke: rgb(46 212 122 / 0.15);
}

.node-automation__alignment-guide {
	pointer-events: none;
	stroke: #ff6b6b;
	stroke-dasharray: 4 3;
	stroke-width: 1px;
}

.node-automation__node {
	align-items: center;
	background: #181818;
	border: 2px solid #7d32d4;
	border-radius: 6px;
	box-shadow: 0 10px 24px rgb(0 0 0 / 0.28);
	color: white;
	cursor: grab;
	display: grid;
	gap: 0.45rem 0.65rem;
	grid-template-columns: 2rem minmax(0, 1fr) auto;
	grid-template-rows: auto;
	min-height: 74px;
	padding: 0.7rem;
	position: absolute;
	text-align: left;
	touch-action: none;
	width: 220px;
	z-index: 2;
}

.node-automation__handle {
	background: #111;
	border: 2px solid #e9aaff;
	border-radius: 999px;
	height: 0.85rem;
	position: absolute;
	top: 50%;
	transform: translateY(-50%);
	width: 0.85rem;
}

.node-automation__handle--in {
	left: -0.5rem;
}

.node-automation__handle--out {
	right: -0.5rem;
}

.node-automation__node.drop-target .node-automation__handle--out {
	background: #2ed47a;
	border-color: #d2ffe3;
}

.node-automation__node:active {
	cursor: grabbing;
}

.node-automation__node.selected {
	border-color: #ffdf6b;
	box-shadow: 0 0 0 3px rgb(255 223 107 / 0.2), 0 12px 28px rgb(0 0 0 / 0.35);
}

.node-automation__node.preview-active {
	border-color: #2ed47a;
	box-shadow: 0 0 0 4px rgb(46 212 122 / 0.28), 0 0 30px rgb(46 212 122 / 0.22), 0 12px 28px rgb(0 0 0 / 0.35);
}

.node-automation__node.drop-target {
	border-color: #2ed47a;
	box-shadow: 0 0 0 4px rgb(46 212 122 / 0.22), 0 12px 28px rgb(0 0 0 / 0.35);
}

.node-automation__node--trigger {
	background: #40256c;
	border-color: #e9aaff;
}

.node-automation__node--action {
	background: #151515;
	border-color: #7d32d4;
}

.node-automation__node--time {
	border-color: #68d391;
}

.node-automation__node--flow {
	border-color: #64b5f6;
}

.node-automation__node--floating {
	border-color: #ff9bd7;
}

.node-automation__node--trigger .node-automation__node-badge {
	background: #ffdf6b;
}

.node-automation__node-icon {
	align-items: center;
	background: rgb(255 255 255 / 0.12);
	border-radius: 4px;
	display: flex;
	font-size: 1.25rem;
	height: 2rem;
	justify-content: center;
}

.node-automation__node-text {
	display: grid;
	min-width: 0;
}

.node-automation__node-text strong,
.node-automation__node-text small {
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.node-automation__node-text small {
	color: #d6d6d6;
	font-size: 0.78rem;
}

.node-automation__node-badge {
	background: #e9aaff;
	border-radius: 4px;
	color: #1b0f21;
	font-size: 0.7rem;
	font-weight: 700;
	padding: 0.2rem 0.35rem;
}

.node-automation__node-config {
	border-top: 1px solid rgb(255 255 255 / 0.1);
	display: grid;
	gap: 0;
	grid-column: 1 / -1;
	margin: 0;
	padding-top: 0.3rem;
}

.node-automation__node-config-line {
	display: flex;
	gap: 0.35rem;
	line-height: 1.25;
}

.node-automation__node-config-line dt {
	color: #b0b0b0;
	flex-shrink: 0;
	font-size: 0.68rem;
	font-weight: 600;
	max-width: 5.5rem;
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.node-automation__node-config-line dd {
	color: #e9e9e9;
	flex: 1;
	font-size: 0.68rem;
	margin: 0;
	min-width: 0;
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.node-automation__context-menu {
	background: var(--surface-b);
	border: 1px solid var(--surface-d);
	border-radius: 3px;
	box-shadow: 0 18px 45px rgb(0 0 0 / 0.42);
	color: var(--text-color);
	display: grid;
	gap: 0.35rem;
	max-height: min(32rem, calc(100vh - 1rem));
	overflow: auto;
	padding: 0.35rem;
	position: fixed;
	width: 340px;
	z-index: 20;
}

.node-automation__context-menu-header {
	align-items: center;
	background: var(--surface-c);
	border: 1px solid var(--surface-d);
	border-radius: 2px;
	display: flex;
	justify-content: space-between;
	padding: 0.5rem 0.55rem;
}

.node-automation__context-menu-header div {
	display: grid;
	gap: 0.1rem;
	min-width: 0;
}

.node-automation__context-menu-header span {
	color: var(--text-color-secondary);
	font-size: 0.75rem;
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.node-automation__context-menu-header button {
	align-items: center;
	background: var(--surface-700);
	border: 1px solid var(--surface-d);
	border-radius: 2px;
	color: var(--text-color);
	cursor: pointer;
	display: flex;
	height: 1.65rem;
	justify-content: center;
	width: 1.65rem;
}

.node-automation__context-menu-search {
	align-items: center;
	background: var(--surface-a);
	border: 1px solid var(--surface-d);
	border-radius: 2px;
	display: grid;
	gap: 0.35rem;
	grid-template-columns: 1rem 1fr;
	padding: 0.35rem 0.45rem;
}

.node-automation__context-menu-search input {
	background: transparent;
	border: 0;
	color: var(--text-color);
	min-width: 0;
	outline: 0;
}

.node-automation__menu-section {
	border: 1px solid var(--surface-d);
	border-radius: 2px;
	overflow: hidden;
}

.node-automation__menu-section-header,
.node-automation__menu-group-header {
	align-items: center;
	background: var(--surface-c);
	border: 0;
	border-bottom: 1px solid var(--surface-d);
	color: var(--text-color);
	cursor: pointer;
	display: flex;
	font-weight: 700;
	justify-content: space-between;
	padding: 0.45rem 0.55rem;
	width: 100%;
}

.node-automation__menu-section-header span,
.node-automation__menu-group-header span {
	align-items: center;
	display: flex;
	gap: 0.4rem;
	min-width: 0;
}

.node-automation__menu-groups {
	background: var(--surface-b);
	display: grid;
}

.node-automation__menu-group + .node-automation__menu-group {
	border-top: 1px solid var(--surface-d);
}

.node-automation__menu-group-header {
	background: var(--surface-a);
	font-size: 0.86rem;
	font-weight: 600;
	padding-left: 0.75rem;
}

.node-automation__menu-items {
	display: grid;
	padding: 0.2rem;
}

.node-automation__menu-items button {
	align-items: center;
	background: transparent;
	border: 1px solid transparent;
	border-radius: 2px;
	color: var(--text-color);
	cursor: pointer;
	display: grid;
	gap: 0.45rem;
	grid-template-columns: 1.35rem minmax(0, 1fr) auto;
	padding: 0.42rem 0.45rem;
	text-align: left;
}

.node-automation__menu-items button:hover {
	background: color-mix(in srgb, #8b35e6 24%, var(--surface-a));
	border-color: #8b35e6;
}

.node-automation__menu-items span {
	display: grid;
	min-width: 0;
}

.node-automation__menu-items strong,
.node-automation__menu-items small {
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.node-automation__menu-items small {
	color: var(--text-color-secondary);
	font-size: 0.72rem;
}

.node-automation__menu-items em {
	background: #7d32d4;
	border-radius: 3px;
	color: white;
	font-size: 0.66rem;
	font-style: normal;
	font-weight: 700;
	padding: 0.12rem 0.28rem;
}

.node-automation__menu-items em.trigger {
	background: #c24cff;
	color: #19001f;
}

.node-automation__details {
	background: #111;
	border-left: 1px solid #343434;
	display: flex;
	flex-direction: column;
	gap: 0.85rem;
	padding: 1rem;
}

.node-automation__details.empty {
	justify-content: flex-start;
}

.node-automation__details-header {
	align-items: flex-start;
	display: flex;
	gap: 0.75rem;
	justify-content: space-between;
}

.node-automation__icon-button {
	align-items: center;
	background: #2c2c2c;
	border: 1px solid #454545;
	border-radius: 4px;
	color: var(--text-color);
	cursor: pointer;
	display: flex;
	height: 2rem;
	justify-content: center;
	width: 2rem;
}

.node-automation__context-section {
	background: #181818;
	border: 1px solid #303030;
	border-radius: 6px;
	overflow: hidden;
}

.node-automation__context-header {
	align-items: center;
	background: #222;
	border: 0;
	color: var(--text-color);
	cursor: pointer;
	display: flex;
	font-weight: 700;
	justify-content: space-between;
	padding: 0.7rem 0.8rem;
	width: 100%;
}

.node-automation__context-header span {
	align-items: center;
	display: flex;
	gap: 0.45rem;
}

.node-automation__config {
	max-height: 52vh;
	overflow: auto;
	padding: 0.55rem;
}

.node-automation__quick-actions {
	display: grid;
	gap: 0.5rem;
	padding: 0.65rem;
}

.node-automation__action-picker {
	display: grid;
	gap: 0.5rem;
}

.node-automation__action-picker label {
	display: grid;
	gap: 0.3rem;
}

.node-automation__action-picker span {
	color: #d9d9d9;
	font-size: 0.78rem;
}

.node-automation__action-picker input,
.node-automation__action-picker select {
	background: #0e0e0e;
	border: 1px solid #4d4d4d;
	border-radius: 4px;
	color: var(--text-color);
	min-width: 0;
	padding: 0.55rem;
}

.node-automation__action-grid {
	display: grid;
	gap: 0.5rem;
	grid-template-columns: 1fr 1fr;
}

.node-automation__palette-list {
	display: grid;
	gap: 0.35rem;
	max-height: 13rem;
	overflow: auto;
	padding-right: 0.15rem;
}

.node-automation__palette-list button {
	align-items: center;
	background: #151515;
	border: 1px solid #3d3d3d;
	border-radius: 4px;
	color: var(--text-color);
	cursor: grab;
	display: grid;
	gap: 0.4rem;
	grid-template-columns: 1.25rem minmax(4rem, 0.7fr) minmax(0, 1fr);
	padding: 0.45rem 0.5rem;
	text-align: left;
}

.node-automation__palette-list button:active {
	cursor: grabbing;
}

.node-automation__palette-list span,
.node-automation__palette-list strong {
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.node-automation__palette-list span {
	color: #bbb;
}

.node-automation__quick-actions button {
	align-items: center;
	background: #2b173d;
	border: 1px solid #7041a6;
	border-radius: 4px;
	color: var(--text-color);
	cursor: pointer;
	display: flex;
	gap: 0.45rem;
	padding: 0.65rem 0.75rem;
	text-align: left;
}

.node-automation__quick-actions button.danger {
	background: #3a171b;
	border-color: #8f3744;
}

.node-automation__quick-actions button:disabled {
	cursor: not-allowed;
	opacity: 0.45;
}

.node-automation__details dl {
	display: grid;
	gap: 0.75rem;
	margin: 0;
	padding: 0.75rem;
}

.node-automation__activity {
	display: grid;
	gap: 0.55rem;
	list-style: none;
	margin: 0;
	padding: 0.65rem;
}

.node-automation__activity li {
	background: #101010;
	border: 1px solid #303030;
	border-radius: 4px;
	display: grid;
	gap: 0.2rem;
	padding: 0.55rem;
}

.node-automation__activity span {
	color: #bbb;
	font-size: 0.8rem;
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.node-automation__details dl div {
	display: grid;
	gap: 0.2rem;
}

.node-automation__details dt {
	color: #aaa;
	font-size: 0.78rem;
}

.node-automation__details dd {
	margin: 0;
	overflow-wrap: anywhere;
}

.node-automation__hint {
	color: #cfcfcf;
	line-height: 1.45;
	margin: 0;
}

.node-automation__classic {
	flex: 1;
	min-height: 0;
}
</style>
