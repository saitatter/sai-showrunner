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
			>
				<div class="node-automation__canvas-controls">
					<button type="button" aria-label="Zoom out" @click="setZoom(zoom - ZOOM_STEP)">
						<i class="mdi mdi-magnify-minus-outline" />
					</button>
					<span>{{ Math.round(zoom * 100) }}%</span>
					<button type="button" aria-label="Zoom in" @click="setZoom(zoom + ZOOM_STEP)">
						<i class="mdi mdi-magnify-plus-outline" />
					</button>
					<button type="button" aria-label="Fit graph" @click="fitGraph">
						<i class="mdi mdi-fit-to-screen-outline" />
					</button>
					<button type="button" aria-label="Reset view" @click="resetView">
						<i class="mdi mdi-backup-restore" />
					</button>
					<button
						type="button"
						:class="{ active: snapToGrid }"
						aria-label="Toggle snap to grid"
						@click="snapToGrid = !snapToGrid"
					>
						<i class="mdi mdi-grid" />
					</button>
				</div>

				<div
					class="node-automation__surface"
					:style="{
						width: `${canvasSize.width}px`,
						height: `${canvasSize.height}px`,
						transform: `translate(${pan.x}px, ${pan.y}px) scale(${zoom})`,
					}"
				>
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
					</svg>

					<button
						v-for="node in nodes"
						:key="node.id"
						class="node-automation__node"
						:class="[
							`node-automation__node--${node.kind}`,
							{ selected: selectedNodeId === node.id, 'drop-target': dropTargetNodeId === node.id },
						]"
						:style="{ transform: `translate(${node.x}px, ${node.y}px)` }"
						type="button"
						@pointerdown.stop="startDrag($event, node)"
						@click.stop="selectedNodeId = node.id"
						@contextmenu.prevent.stop="openNodeContext(node)"
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
						<span
							v-if="node.id !== 'trigger'"
							class="node-automation__handle node-automation__handle--out"
							title="Drop an action here to insert after this node"
						/>
					</button>
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
						@click="selectedNodeId = undefined"
					>
						<i class="mdi mdi-close" />
					</button>
				</header>

				<template v-if="selectedNode">
					<section class="node-automation__context-section">
						<button type="button" class="node-automation__context-header" @click="detailsOpen = !detailsOpen">
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
							<button type="button" class="node-automation__context-header" @click="configOpen = !configOpen">
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
						<button type="button" class="node-automation__context-header" @click="actionsOpen = !actionsOpen">
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
					<button type="button" class="node-automation__context-header" @click="activityOpen = !activityOpen">
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
import { computed, onMounted, onUnmounted, ref, useModel, watch } from "vue"
import {
	ActionSelection,
	AutomationConfig,
	AutomationResourceView,
	AutomationEdit,
	DataBindingPath,
	usePluginStore,
} from "castmate-ui-core"
import ActionConfigEdit from "../../../../../../libs/castmate-ui-core/src/components/automation/ActionConfigEdit.vue"
import TriggerConfigEdit from "../../../../../../libs/castmate-ui-core/src/components/automation/TriggerConfigEdit.vue"
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
} from "castmate-schema"

interface NodePosition {
	x: number
	y: number
}

interface NodeData extends NodePosition {
	id: string
	kind: "trigger" | "action" | "stack" | "time" | "flow" | "floating"
	title: string
	subtitle: string
	icon: string
	badge?: string
	path?: string
}

interface EdgeData {
	id: string
	from: string
	to: string
	path: string
}

interface NodeEditorViewState {
	zoom?: number
	pan?: NodePosition
	snapToGrid?: boolean
}

const props = defineProps<{
	modelValue: AutomationConfig
	view: AutomationResourceView & { nodePositions?: Record<string, NodePosition>; nodeView?: NodeEditorViewState }
}>()

const model = useModel(props, "modelValue")
const view = useModel(props, "view")
const mode = ref<"nodes" | "timeline">("nodes")
const selectedNodeId = ref<string>()
const selectedActionToAdd = ref("")
const actionPaletteQuery = ref("")
const canvasRef = ref<HTMLElement>()
const zoom = ref(props.view.nodeView?.zoom ?? 1)
const pan = ref(props.view.nodeView?.pan ?? { x: 0, y: 0 })
const isPanning = ref(false)
const snapToGrid = ref(props.view.nodeView?.snapToGrid ?? true)
const dropTargetNodeId = ref<string>()
const dropTargetEdgeId = ref<string>()
const detailsOpen = ref(true)
const configOpen = ref(true)
const actionsOpen = ref(false)
const activityOpen = ref(true)
const activityLog = ref<Array<{ id: number; title: string; detail: string }>>([])
const pluginStore = usePluginStore()

const NODE_WIDTH = 220
const NODE_HEIGHT = 74
const H_GAP = 285
const V_GAP = 128
const GRID_SIZE = 42
const MIN_ZOOM = 0.35
const MAX_ZOOM = 1.5
const ZOOM_STEP = 0.1

const nodePositions = computed(() => {
	view.value.nodePositions ??= {}
	return view.value.nodePositions
})

watch(
	[zoom, pan, snapToGrid],
	() => {
		view.value.nodeView = {
			zoom: zoom.value,
			pan: pan.value,
			snapToGrid: snapToGrid.value,
		}
	},
	{ deep: true, immediate: true }
)

const graph = computed(() => buildGraph(model.value))
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
		const startY = from.y + NODE_HEIGHT / 2
		const endX = to.x
		const endY = to.y + NODE_HEIGHT / 2
		const midX = startX + Math.max(60, (endX - startX) / 2)
		return [
			{
				...edge,
				path: `M ${startX} ${startY} C ${midX} ${startY}, ${midX} ${endY}, ${endX} ${endY}`,
			},
		]
	})
})
const selectedNode = computed(() => nodes.value.find((node) => node.id === selectedNodeId.value))
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
	height: Math.max(720, ...nodes.value.map((node) => node.y + NODE_HEIGHT + 160)),
}))
const graphBounds = computed(() => {
	const minX = Math.min(42, ...nodes.value.map((node) => node.x))
	const minY = Math.min(88, ...nodes.value.map((node) => node.y))
	const maxX = Math.max(...nodes.value.map((node) => node.x + NODE_WIDTH))
	const maxY = Math.max(...nodes.value.map((node) => node.y + NODE_HEIGHT))
	return { minX, minY, width: maxX - minX, height: maxY - minY }
})

function buildGraph(automation: AutomationConfig) {
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
	})

	const mainNodes = addSequence(nodes, edges, automation.sequence, "sequence", 1, 0, "Main")
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
		})
		const childNodes = addSequence(nodes, edges, sequence, `floatingSequences[${index}]`, 1, index + 2, `Floating ${index + 1}`)
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
	group: string
) {
	const ids: string[] = []
	sequence.actions.forEach((action, index) => {
		const node = createNode(action, `${path}.actions[${index}]`, column + index, row, group)
		nodes.push(node)
		ids.push(node.id)

		if (index > 0) {
			edges.push({ id: `${ids[index - 1]}:${node.id}`, from: ids[index - 1], to: node.id })
		}

		if (isActionStack(action)) {
			action.stack.forEach((stackAction, stackIndex) => {
				const child = createNode(stackAction, `${node.path}.stack[${stackIndex}]`, column + index, row + stackIndex + 1, "Stack")
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
					`+${offset.offset}s`
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
					`Flow ${flowIndex + 1}`
				)
				if (children[0]) edges.push({ id: `${node.id}:${children[0]}`, from: node.id, to: children[0] })
			})
		}
	})
	return ids
}

function createNode(action: AnyAction | ActionStack, path: string, column: number, row: number, group: string): NodeData {
	if (isActionStack(action)) {
		return {
			id: action.id,
			kind: "stack",
			title: "Action Stack",
			subtitle: `${action.stack.length} stacked action${action.stack.length === 1 ? "" : "s"}`,
			icon: "mdi mdi-layers-triple",
			badge: group,
			x: 42 + column * H_GAP,
			y: 88 + row * V_GAP,
			path,
		}
	}

	return {
		id: action.id,
		kind: isFlowAction(action) ? "flow" : isTimeAction(action) ? "time" : "action",
		title: titleCase(action.action),
		subtitle: `${action.plugin} / ${action.action}`,
		icon: isFlowAction(action) ? "mdi mdi-source-branch" : isTimeAction(action) ? "mdi mdi-timer-outline" : "mdi mdi-play",
		badge: group,
		x: 42 + column * H_GAP,
		y: 88 + row * V_GAP,
		path,
	}
}

function titleCase(value: string) {
	return value
		.replace(/[-_]/g, " ")
		.replace(/([a-z])([A-Z])/g, "$1 $2")
		.replace(/\b\w/g, (letter) => letter.toUpperCase())
}

function startDrag(event: PointerEvent, node: NodeData) {
	selectedNodeId.value = node.id
	const startX = event.clientX
	const startY = event.clientY
	const initial = nodePositions.value[node.id] ?? { x: node.x, y: node.y }
	const target = event.currentTarget as HTMLElement
	target.setPointerCapture(event.pointerId)

	function onMove(moveEvent: PointerEvent) {
		const nextX = Math.max(12, initial.x + (moveEvent.clientX - startX) / zoom.value)
		const nextY = Math.max(12, initial.y + (moveEvent.clientY - startY) / zoom.value)
		nodePositions.value[node.id] = {
			x: snapCoordinate(nextX),
			y: snapCoordinate(nextY),
		}
	}

	function onUp(upEvent: PointerEvent) {
		target.releasePointerCapture(upEvent.pointerId)
		target.removeEventListener("pointermove", onMove)
		target.removeEventListener("pointerup", onUp)
		target.removeEventListener("pointercancel", onUp)
	}

	target.addEventListener("pointermove", onMove)
	target.addEventListener("pointerup", onUp)
	target.addEventListener("pointercancel", onUp)
}

function openNodeContext(node: NodeData) {
	selectedNodeId.value = node.id
	detailsOpen.value = true
	configOpen.value = true
	actionsOpen.value = false
}

function resetSelectedNodePosition() {
	if (!selectedNodeId.value) return
	delete nodePositions.value[selectedNodeId.value]
}

function setZoom(nextZoom: number) {
	zoom.value = Math.max(MIN_ZOOM, Math.min(MAX_ZOOM, Number(nextZoom.toFixed(2))))
}

function snapCoordinate(value: number) {
	if (!snapToGrid.value) return value
	return Math.round(value / GRID_SIZE) * GRID_SIZE
}

function zoomFromWheel(event: WheelEvent) {
	setZoom(zoom.value + (event.deltaY > 0 ? -ZOOM_STEP : ZOOM_STEP))
}

function fitGraph() {
	const canvas = canvasRef.value
	if (!canvas) return
	const availableWidth = Math.max(1, canvas.clientWidth - 56)
	const availableHeight = Math.max(1, canvas.clientHeight - 56)
	const bounds = graphBounds.value
	const widthScale = availableWidth / Math.max(1, bounds.width)
	const heightScale = availableHeight / Math.max(1, bounds.height)
	setZoom(Math.min(widthScale, heightScale, 1))
	pan.value = { x: 0, y: 0 }
	canvas.scrollTo({
		left: Math.max(0, bounds.minX * zoom.value - 28),
		top: Math.max(0, bounds.minY * zoom.value - 28),
		behavior: "smooth",
	})
}

function resetView() {
	zoom.value = 1
	pan.value = { x: 0, y: 0 }
	canvasRef.value?.scrollTo({ left: 0, top: 0, behavior: "smooth" })
}

function handleCanvasPointerDown(event: PointerEvent) {
	const target = event.target as HTMLElement
	if (target.closest(".node-automation__canvas-controls")) return

	const isCanvasTarget =
		target.classList.contains("node-automation__canvas") ||
		target.classList.contains("node-automation__surface") ||
		target.classList.contains("node-automation__edges")

	if (isCanvasTarget) selectedNodeId.value = undefined
	if (event.button === 1 && isCanvasTarget) {
		event.preventDefault()
		startPan(event)
	}
}

function startPan(event: PointerEvent) {
	const canvas = canvasRef.value
	if (!canvas) return

	isPanning.value = true
	const startX = event.clientX
	const startY = event.clientY
	const initialPan = { ...pan.value }
	canvas.setPointerCapture(event.pointerId)

	function onMove(moveEvent: PointerEvent) {
		pan.value = {
			x: initialPan.x + moveEvent.clientX - startX,
			y: initialPan.y + moveEvent.clientY - startY,
		}
	}

	function onUp(upEvent: PointerEvent) {
		isPanning.value = false
		canvas.releasePointerCapture(upEvent.pointerId)
		canvas.removeEventListener("pointermove", onMove)
		canvas.removeEventListener("pointerup", onUp)
		canvas.removeEventListener("pointercancel", onUp)
	}

	canvas.addEventListener("pointermove", onMove)
	canvas.addEventListener("pointerup", onUp)
	canvas.addEventListener("pointercancel", onUp)
}

function handleKeydown(event: KeyboardEvent) {
	if (mode.value !== "nodes") return
	const target = event.target as HTMLElement | null
	if (target?.closest("input, textarea, select, [contenteditable='true']")) return

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

	selectedNodeId.value = action.id
	configOpen.value = true
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
	selectedNodeId.value = action.id
	configOpen.value = true
	dropTargetNodeId.value = undefined
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
	selectedNodeId.value = action.id
	configOpen.value = true
	dropTargetNodeId.value = undefined
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
	selectedNodeId.value = action.id
	configOpen.value = true
	dropTargetEdgeId.value = undefined
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
	selectedNodeId.value = clonedAction.id
	configOpen.value = true
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
}

function getNodePosition(nodeId: string) {
	const info = findActionAndSequenceById(nodeId, model.value)
	if (!info) return undefined
	return getPathPosition(info.path)
}

function getCanvasPoint(event: DragEvent): NodePosition {
	const surface = canvasRef.value?.querySelector<HTMLElement>(".node-automation__surface")
	const rect = surface?.getBoundingClientRect()
	if (!rect) return { x: 42, y: 88 }
	return {
		x: snapCoordinate(Math.max(12, (event.clientX - rect.left) / zoom.value)),
		y: snapCoordinate(Math.max(12, (event.clientY - rect.top) / zoom.value)),
	}
}

function logActivity(title: string, detail: string) {
	activityLog.value.unshift({ id: Date.now() + Math.random(), title, detail })
	activityLog.value = activityLog.value.slice(0, 8)
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

onMounted(() => window.addEventListener("keydown", handleKeydown))
onUnmounted(() => window.removeEventListener("keydown", handleKeydown))
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

.node-automation__surface {
	position: relative;
	transform-origin: 0 0;
}

.node-automation__edges {
	inset: 0;
	min-height: 100%;
	min-width: 100%;
	position: absolute;
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

.node-automation__node {
	align-items: center;
	background: #181818;
	border: 2px solid #7d32d4;
	border-radius: 6px;
	box-shadow: 0 10px 24px rgb(0 0 0 / 0.28);
	color: white;
	cursor: grab;
	display: grid;
	gap: 0.65rem;
	grid-template-columns: 2rem minmax(0, 1fr) auto;
	height: 74px;
	padding: 0.7rem;
	position: absolute;
	text-align: left;
	touch-action: none;
	width: 220px;
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

.node-automation__node.drop-target {
	border-color: #2ed47a;
	box-shadow: 0 0 0 4px rgb(46 212 122 / 0.22), 0 12px 28px rgb(0 0 0 / 0.35);
}

.node-automation__node--trigger {
	background: #40256c;
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
