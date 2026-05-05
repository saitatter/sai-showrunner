<template>
	<div class="shader-graph">
		<header class="shader-graph__toolbar">
			<h3><i class="mdi mdi-magic-staff" /> Shader Graph</h3>
			<div class="shader-graph__toolbar-actions">
				<button type="button" @click="compileAndApply" v-tooltip="'Compile & Apply'">
					<i class="mdi mdi-play" /> Compile
				</button>
				<button type="button" @click="fitGraph" v-tooltip="'Fit graph'">
					<i class="mdi mdi-fit-to-screen-outline" />
				</button>
				<button type="button" @click="resetGraph" v-tooltip="'Reset graph'">
					<i class="mdi mdi-restore" />
				</button>
				<button type="button" @click="sidePanelTab = 'code'" :class="{ active: sidePanelTab === 'code' }">
					<i class="mdi mdi-code-tags" /> GLSL
				</button>
			</div>
		</header>

		<div class="shader-graph__body">
			<aside class="shader-graph__palette">
				<label class="shader-graph__palette-search">
					<i class="mdi mdi-magnify" />
					<input
						v-model="paletteQuery"
						type="search"
						placeholder="Search nodes..."
					/>
				</label>
				<div class="shader-graph__palette-list">
					<template v-for="cat in filteredCategories" :key="cat.name">
						<div class="shader-graph__palette-category">{{ cat.name }}</div>
						<button
							v-for="def in cat.defs"
							:key="def.id"
							type="button"
							@click="addNodeFromPalette(def.id)"
						>
							<i :class="def.icon" />
							{{ def.name }}
						</button>
					</template>
				</div>
			</aside>

			<section
				ref="canvasRef"
				class="shader-graph__canvas"
				@pointerdown="onCanvasPointerDown"
				@contextmenu.prevent="openPalette"
				@wheel.ctrl.prevent="onZoom"
			>
				<div
					class="shader-graph__surface"
					:style="{
						transform: `translate(${pan.x}px, ${pan.y}px) scale(${zoom})`,
						width: `${surfaceSize.width}px`,
						height: `${surfaceSize.height}px`,
					}"
				>
					<!-- Wires SVG -->
					<svg class="shader-graph__wires" :viewBox="`0 0 ${surfaceSize.width} ${surfaceSize.height}`">
						<path
							v-for="wire in wirePaths"
							:key="wire.id"
							class="shader-graph__wire"
							:class="{ selected: selectedWireId === wire.id }"
							:d="wire.path"
							:stroke="wire.color"
							vector-effect="non-scaling-stroke"
							@click.stop="selectedWireId = wire.id"
						/>
						<path
							v-if="dragWire"
							class="shader-graph__wire shader-graph__wire--dragging"
							:d="dragWire.path"
							stroke="#fff8"
							vector-effect="non-scaling-stroke"
						/>
					</svg>

					<!-- Nodes -->
					<div
						v-for="node in graphNodes"
						:key="node.id"
						class="shader-graph__node"
						:class="{ selected: selectedNodeId === node.id, output: node.defId === 'fragment_output' }"
						:style="{ transform: `translate(${node.x}px, ${node.y}px)` }"
						@pointerdown.stop="startNodeDrag($event, node)"
						@click.stop="selectedNodeId = node.id"
					>
						<header class="shader-graph__node-header" :style="{ background: categoryColor(node.category) }">
							<i :class="node.icon" />
							<span>{{ node.name }}</span>
						</header>

						<!-- Preview canvas -->
						<canvas
							v-if="node.defId !== 'float_const' && node.defId !== 'vec3_const'"
							:ref="(el) => setPreviewRef(node.id, el as HTMLCanvasElement)"
							class="shader-graph__node-preview"
							width="160"
							height="80"
						/>

						<!-- Input ports -->
						<div class="shader-graph__ports">
							<div class="shader-graph__port-column shader-graph__port-column--in">
								<div
									v-for="port in node.inputs"
									:key="port.key"
									class="shader-graph__port"
								>
									<span
										class="shader-graph__port-dot"
										:data-shader-port-node-id="node.id"
										:data-shader-port-key="port.key"
										:data-shader-port-kind="'in'"
										:style="{ background: typeColor(port.type) }"
										@pointerdown.stop="startWireDrag($event, node.id, port.key, 'in', port.type)"
									/>
									<span class="shader-graph__port-name">{{ port.label }}</span>
									<span class="shader-graph__port-type">{{ port.type }}</span>
								</div>
							</div>
							<div class="shader-graph__port-column shader-graph__port-column--out">
								<div
									v-for="port in node.outputs"
									:key="port.key"
									class="shader-graph__port shader-graph__port--out"
								>
									<span class="shader-graph__port-type">{{ port.type }}</span>
									<span class="shader-graph__port-name">{{ port.label }}</span>
									<span
										class="shader-graph__port-dot"
										:data-shader-port-node-id="node.id"
										:data-shader-port-key="port.key"
										:data-shader-port-kind="'out'"
										:style="{ background: typeColor(port.type) }"
										@pointerdown.stop="startWireDrag($event, node.id, port.key, 'out', port.type)"
									/>
								</div>
							</div>
						</div>
					</div>
				</div>

				<!-- Node palette (right-click) -->
				<div
					v-if="paletteOpen"
				>
					<collapsible-context-menu
						:x="palettePos.x"
						:y="palettePos.y"
						title="Shader Nodes"
						subtitle="Add procedural building blocks"
						width="320px"
						@close="paletteOpen = false"
					>
						<template #search>
							<label class="shader-graph__palette-search">
								<i class="mdi mdi-magnify" />
								<input
									ref="paletteInputRef"
									v-model="paletteQuery"
									type="search"
									placeholder="Search nodes..."
									@keydown.escape.prevent="paletteOpen = false"
								/>
							</label>
						</template>
						<div class="shader-graph__palette-list">
							<template v-for="cat in filteredCategories" :key="cat.name">
								<div class="shader-graph__palette-category">{{ cat.name }}</div>
								<button
									v-for="def in cat.defs"
									:key="def.id"
									type="button"
									@click="addNode(def.id)"
								>
									<i :class="def.icon" />
									{{ def.name }}
								</button>
							</template>
						</div>
					</collapsible-context-menu>
				</div>
			</section>

			<aside class="shader-graph__side-panel">
				<header class="shader-graph__tabs">
					<button type="button" :class="{ active: sidePanelTab === 'preview' }" @click="sidePanelTab = 'preview'">
						<i class="mdi mdi-eye-outline" /> Preview
					</button>
					<button type="button" :class="{ active: sidePanelTab === 'errors' }" @click="sidePanelTab = 'errors'">
						<i class="mdi mdi-alert-circle-outline" /> Errors {{ compileErrors.length }}
					</button>
					<button type="button" :class="{ active: sidePanelTab === 'code' }" @click="sidePanelTab = 'code'">
						<i class="mdi mdi-code-tags" /> GLSL
					</button>
				</header>

				<section v-if="sidePanelTab === 'preview'" class="shader-graph__preview-panel">
					<canvas ref="livePreviewCanvas" class="shader-graph__live-preview" width="320" height="180" />
					<p v-if="!previewError && !lastPreviewGlsl" class="shader-graph__preview-hint">
						<i class="mdi mdi-information-outline" /> Compile a valid graph to preview it here.
					</p>
					<p v-if="previewError" class="shader-graph__preview-error">
						<i class="mdi mdi-alert" /> {{ previewError }}
					</p>
				</section>

				<section v-else-if="sidePanelTab === 'errors'" class="shader-graph__errors">
					<p v-if="!compileErrors.length" class="shader-graph__empty-state">No shader graph errors.</p>
					<p v-for="(err, i) in compileErrors" v-else :key="i"><i class="mdi mdi-alert" /> {{ err }}</p>
				</section>

				<section v-else class="shader-graph__code">
					<header>
						<strong>Generated GLSL</strong>
						<button type="button" @click="copyGlsl" v-tooltip="'Copy to clipboard'">
							<i class="mdi mdi-content-copy" />
						</button>
					</header>
					<pre><code>{{ compiledGlsl }}</code></pre>
				</section>
			</aside>
		</div>
	</div>
</template>

<script setup lang="ts">
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from "vue"
import { CollapsibleContextMenu } from "showrunner-ui-core"
import {
	SHADER_NODE_DEFS,
	SHADER_NODE_DEF_MAP,
	SHADER_NODE_CATEGORIES,
	areShaderTypesCompatible,
	compileShaderGraph,
	type ShaderGraph,
	type ShaderNodeInstance,
	type ShaderNodeDef,
	type GlslType,
} from "./shader-nodes"
import { createDefaultShaderGraph, cloneShaderGraph } from "./shader-graph-state"

const props = defineProps<{
	modelValue: ShaderGraph
}>()

const emit = defineEmits<{
	"update:modelValue": [graph: ShaderGraph]
	"compile": [glsl: string]
}>()

// ─── State ───────────────────────────────────────────────────────────
const canvasRef = ref<HTMLElement>()
const paletteInputRef = ref<HTMLInputElement>()
const livePreviewCanvas = ref<HTMLCanvasElement>()
const zoom = ref(1)
const pan = ref({ x: 0, y: 0 })
const selectedNodeId = ref<string>()
const selectedWireId = ref<string>()
const paletteOpen = ref(false)
const palettePos = ref({ x: 0, y: 0 })
const paletteQuery = ref("")
const sidePanelTab = ref<"preview" | "errors" | "code">("preview")
const compiledGlsl = ref("")
const compileErrors = ref<string[]>([])
const previewError = ref("")

// Wire drag state
const dragWire = ref<{ path: string; fromNode: string; fromPort: string; fromKind: "in" | "out"; type: GlslType } | null>(null)
let dragState: { fromNode: string; fromPort: string; fromKind: "in" | "out"; fromX: number; fromY: number; type: GlslType } | null = null

// Node preview canvases
const previewRefs = new Map<string, HTMLCanvasElement>()
function setPreviewRef(nodeId: string, el: HTMLCanvasElement | null) {
	if (el) previewRefs.set(nodeId, el)
	else previewRefs.delete(nodeId)
}

// ─── Computed ────────────────────────────────────────────────────────
const graph = computed({
	get: () => props.modelValue,
	set: (v) => emit("update:modelValue", v),
})

function emitGraphUpdate() {
	emit("update:modelValue", cloneShaderGraph(graph.value))
}

interface GraphNode extends ShaderNodeInstance {
	name: string
	icon: string
	category: string
	inputs: ShaderNodeDef["inputs"]
	outputs: ShaderNodeDef["outputs"]
}

const graphNodes = computed<GraphNode[]>(() =>
	graph.value.nodes.map((n) => {
		const def = SHADER_NODE_DEF_MAP.get(n.defId)
		return {
			...n,
			name: def?.name ?? n.defId,
			icon: def?.icon ?? "mdi mdi-help",
			category: def?.category ?? "Unknown",
			inputs: def?.inputs ?? [],
			outputs: def?.outputs ?? [],
		}
	})
)

const NODE_W = 180

const surfaceSize = computed(() => ({
	width: Math.max(1600, ...graphNodes.value.map((n) => n.x + NODE_W + 200)),
	height: Math.max(900, ...graphNodes.value.map((n) => n.y + 200)),
}))

function getPortPos(nodeId: string, portKey: string, kind: "in" | "out"): { x: number; y: number } | undefined {
	const rendered = getRenderedPortPos(nodeId, portKey, kind)
	if (rendered) return rendered

	const node = graphNodes.value.find((n) => n.id === nodeId)
	if (!node) return undefined
	const def = SHADER_NODE_DEF_MAP.get(node.defId)
	if (!def) return undefined
	const ports = kind === "in" ? def.inputs : def.outputs
	const idx = ports.findIndex((p) => p.key === portKey)
	if (idx < 0) return undefined

	const headerH = 28
	const previewH = (node.defId !== "float_const" && node.defId !== "vec3_const") ? 80 : 0
	const portStartY = headerH + previewH + 8
	const portH = 20
	const y = node.y + portStartY + idx * portH + portH / 2

	return {
		x: kind === "in" ? node.x : node.x + NODE_W,
		y,
	}
}

const wirePaths = computed(() =>
	graph.value.wires.flatMap((wire) => {
		const from = getPortPos(wire.fromNode, wire.fromPort, "out")
		const to = getPortPos(wire.toNode, wire.toPort, "in")
		if (!from || !to) return []
		const fromDef = SHADER_NODE_DEF_MAP.get(graphNodes.value.find((n) => n.id === wire.fromNode)?.defId ?? "")
		const portDef = fromDef?.outputs.find((p) => p.key === wire.fromPort)
		return [{
			id: wire.id,
			path: bezier(from.x, from.y, to.x, to.y),
			color: typeColor(portDef?.type ?? "float"),
		}]
	})
)

const filteredCategories = computed(() => {
	const q = paletteQuery.value.toLowerCase().trim()
	return SHADER_NODE_CATEGORIES
		.map((cat) => ({
			name: cat,
			defs: SHADER_NODE_DEFS.filter(
				(d) => d.category === cat && (!q || d.name.toLowerCase().includes(q) || d.category.toLowerCase().includes(q))
			),
		}))
		.filter((cat) => cat.defs.length > 0)
})

// ─── Pan / Zoom ──────────────────────────────────────────────────────
function onZoom(e: WheelEvent) {
	const step = 0.08
	zoom.value = Math.max(0.25, Math.min(2, zoom.value + (e.deltaY > 0 ? -step : step)))
}

function onCanvasPointerDown(e: PointerEvent) {
	if (e.button === 1) {
		e.preventDefault()
		startPan(e)
	}
	if (e.button === 0) {
		selectedNodeId.value = undefined
		selectedWireId.value = undefined
		if (paletteOpen.value) paletteOpen.value = false
	}
}

function startPan(e: PointerEvent) {
	const startX = e.clientX
	const startY = e.clientY
	const startPanX = pan.value.x
	const startPanY = pan.value.y
	function onMove(me: PointerEvent) {
		pan.value = { x: startPanX + me.clientX - startX, y: startPanY + me.clientY - startY }
	}
	function onUp() {
		window.removeEventListener("pointermove", onMove)
		window.removeEventListener("pointerup", onUp)
	}
	window.addEventListener("pointermove", onMove)
	window.addEventListener("pointerup", onUp)
}

function fitGraph() {
	const canvas = canvasRef.value
	if (!canvas || graphNodes.value.length === 0) return
	const minX = Math.min(...graphNodes.value.map((n) => n.x))
	const minY = Math.min(...graphNodes.value.map((n) => n.y))
	const maxX = Math.max(...graphNodes.value.map((n) => n.x + NODE_W))
	const maxY = Math.max(...graphNodes.value.map((n) => n.y + 160))
	const w = maxX - minX
	const h = maxY - minY
	const cw = canvas.clientWidth
	const ch = canvas.clientHeight
	zoom.value = Math.min(1, Math.min(cw / (w + 80), ch / (h + 80)))
	pan.value = { x: (cw - w * zoom.value) / 2 - minX * zoom.value, y: (ch - h * zoom.value) / 2 - minY * zoom.value }
}

// ─── Node Drag ───────────────────────────────────────────────────────
function startNodeDrag(e: PointerEvent, node: GraphNode) {
	selectedNodeId.value = node.id
	const startX = e.clientX
	const startY = e.clientY
	const startNodeX = node.x
	const startNodeY = node.y
	const target = e.currentTarget as HTMLElement
	target.setPointerCapture(e.pointerId)
	function onMove(me: PointerEvent) {
		const dx = (me.clientX - startX) / zoom.value
		const dy = (me.clientY - startY) / zoom.value
		const n = graph.value.nodes.find((nd) => nd.id === node.id)
		if (n) {
			n.x = Math.max(0, Math.round(startNodeX + dx))
			n.y = Math.max(0, Math.round(startNodeY + dy))
		}
	}
	function onUp() {
		target.removeEventListener("pointermove", onMove)
		target.removeEventListener("pointerup", onUp)
		emitGraphUpdate()
		autoCompile()
	}
	target.addEventListener("pointermove", onMove)
	target.addEventListener("pointerup", onUp)
}

// ─── Wire Drag ───────────────────────────────────────────────────────
function startWireDrag(e: PointerEvent, nodeId: string, portKey: string, kind: "in" | "out", type: GlslType) {
	e.preventDefault()
	const pos = getPortPos(nodeId, portKey, kind)
	if (!pos) return

	// If dragging from input that has a wire, disconnect and reverse
	if (kind === "in") {
		const idx = graph.value.wires.findIndex((w) => w.toNode === nodeId && w.toPort === portKey)
		if (idx >= 0) {
			const wire = graph.value.wires[idx]
			graph.value.wires.splice(idx, 1)
			const fromPos = getPortPos(wire.fromNode, wire.fromPort, "out")
			if (fromPos) {
				dragState = { fromNode: wire.fromNode, fromPort: wire.fromPort, fromKind: "out", fromX: fromPos.x, fromY: fromPos.y, type }
				dragWire.value = { path: bezier(fromPos.x, fromPos.y, pos.x, pos.y), fromNode: wire.fromNode, fromPort: wire.fromPort, fromKind: "out", type }
				window.addEventListener("pointermove", onWireMove)
				window.addEventListener("pointerup", onWireUp)
				return
			}
		}
	}

	dragState = { fromNode: nodeId, fromPort: portKey, fromKind: kind, fromX: pos.x, fromY: pos.y, type }
	dragWire.value = { path: bezier(pos.x, pos.y, pos.x, pos.y), fromNode: nodeId, fromPort: portKey, fromKind: kind, type }
	window.addEventListener("pointermove", onWireMove)
	window.addEventListener("pointerup", onWireUp)
}

function onWireMove(e: PointerEvent) {
	if (!dragState || !canvasRef.value) return
	const surface = canvasRef.value.querySelector<HTMLElement>(".shader-graph__surface")
	if (!surface) return
	const rect = surface.getBoundingClientRect()
	const mx = (e.clientX - rect.left) / zoom.value
	const my = (e.clientY - rect.top) / zoom.value
	const isOut = dragState.fromKind === "out"
	dragWire.value = {
		path: isOut ? bezier(dragState.fromX, dragState.fromY, mx, my) : bezier(mx, my, dragState.fromX, dragState.fromY),
		fromNode: dragState.fromNode,
		fromPort: dragState.fromPort,
		fromKind: dragState.fromKind,
		type: dragState.type,
	}
}

function onWireUp(e: PointerEvent) {
	window.removeEventListener("pointermove", onWireMove)
	window.removeEventListener("pointerup", onWireUp)
	if (!dragState) { dragWire.value = null; return }

	// Find port under cursor
	const surface = canvasRef.value?.querySelector<HTMLElement>(".shader-graph__surface")
	if (!surface) { dragWire.value = null; dragState = null; return }
	const rect = surface.getBoundingClientRect()
	const mx = (e.clientX - rect.left) / zoom.value
	const my = (e.clientY - rect.top) / zoom.value
	const targetKind = dragState.fromKind === "out" ? "in" : "out"
	const SNAP = 20
	let connected = false

	for (const node of graphNodes.value) {
		if (node.id === dragState.fromNode) continue
		const ports = targetKind === "in" ? node.inputs : node.outputs
		for (const port of ports) {
			const pos = getPortPos(node.id, port.key, targetKind)
			if (!pos) continue
			const dist = Math.sqrt((pos.x - mx) ** 2 + (pos.y - my) ** 2)
			if (dist < SNAP && areShaderTypesCompatible(dragState.type, port.type)) {
				const fromNode = dragState.fromKind === "out" ? dragState.fromNode : node.id
				const fromPort = dragState.fromKind === "out" ? dragState.fromPort : port.key
				const toNode = dragState.fromKind === "out" ? node.id : dragState.fromNode
				const toPort = dragState.fromKind === "out" ? port.key : dragState.fromPort
				// Remove existing wire to target input
				const existing = graph.value.wires.findIndex((w) => w.toNode === toNode && w.toPort === toPort)
				if (existing >= 0) graph.value.wires.splice(existing, 1)
				graph.value.wires.push({ id: `${fromNode}:${fromPort}->${toNode}:${toPort}`, fromNode, fromPort, toNode, toPort })
				emitGraphUpdate()
				autoCompile()
				connected = true
				break
			}
		}
		if (connected) break
	}

	if (!connected) {
		emitGraphUpdate()
		autoCompile()
	}
	dragWire.value = null
	dragState = null
}

// ─── Palette ─────────────────────────────────────────────────────────
function openPalette(e: MouseEvent) {
	palettePos.value = { x: e.clientX - (canvasRef.value?.getBoundingClientRect().left ?? 0), y: e.clientY - (canvasRef.value?.getBoundingClientRect().top ?? 0) }
	paletteQuery.value = ""
	paletteOpen.value = true
	nextTick(() => paletteInputRef.value?.focus())
}

let nodeCounter = 0
function addNode(defId: string) {
	addNodeAt(defId, {
		x: Math.round((palettePos.value.x - pan.value.x) / zoom.value),
		y: Math.round((palettePos.value.y - pan.value.y) / zoom.value),
	})
	paletteOpen.value = false
}

function addNodeFromPalette(defId: string) {
	const canvas = canvasRef.value
	const x = canvas ? (canvas.clientWidth * 0.5 - pan.value.x) / zoom.value : 240
	const y = canvas ? (canvas.clientHeight * 0.45 - pan.value.y) / zoom.value : 200
	addNodeAt(defId, { x: Math.round(x), y: Math.round(y) })
}

function addNodeAt(defId: string, position: { x: number; y: number }) {
	if (!canvasRef.value) return
	const id = `sn_${Date.now()}_${nodeCounter++}`
	graph.value.nodes.push({ id, defId, x: Math.max(0, position.x), y: Math.max(0, position.y) })
	if (defId === "fragment_output") graph.value.outputNodeId = id
	emitGraphUpdate()
	autoCompile()
}

// ─── Compile ─────────────────────────────────────────────────────────
function autoCompile() {
	const result = compileShaderGraph(graph.value)
	compiledGlsl.value = result.glsl
	compileErrors.value = result.errors
	if (result.errors.length) {
		previewError.value = result.errors[0]
		return
	}
	if (!result.errors.length && result.glsl) {
		updateLivePreview(result.glsl)
	}
}

function compileAndApply() {
	autoCompile()
	if (!compileErrors.value.length && compiledGlsl.value) {
		emit("compile", compiledGlsl.value)
		sidePanelTab.value = "preview"
	} else {
		sidePanelTab.value = "errors"
	}
}

function getRenderedPortPos(nodeId: string, portKey: string, kind: "in" | "out"): { x: number; y: number } | undefined {
	const surface = canvasRef.value?.querySelector<HTMLElement>(".shader-graph__surface")
	if (!surface) return undefined

	const elements = surface.querySelectorAll<HTMLElement>("[data-shader-port-node-id]")
	const element = [...elements].find((item) =>
		item.dataset.shaderPortNodeId === nodeId &&
		item.dataset.shaderPortKey === portKey &&
		item.dataset.shaderPortKind === kind
	)
	if (!element) return undefined

	const surfaceRect = surface.getBoundingClientRect()
	const portRect = element.getBoundingClientRect()
	return {
		x: (portRect.left + portRect.width / 2 - surfaceRect.left) / zoom.value,
		y: (portRect.top + portRect.height / 2 - surfaceRect.top) / zoom.value,
	}
}

function resetGraph() {
	graph.value = createDefaultShaderGraph()
	emitGraphUpdate()
	autoCompile()
	fitGraph()
}

function copyGlsl() {
	if (compiledGlsl.value) navigator.clipboard.writeText(compiledGlsl.value).catch(() => {})
}

// ─── Keyboard ────────────────────────────────────────────────────────
function onKeyDown(e: KeyboardEvent) {
	if ((e.key === "Delete" || e.key === "Backspace") && selectedWireId.value) {
		e.preventDefault()
		const idx = graph.value.wires.findIndex((w) => w.id === selectedWireId.value)
		if (idx >= 0) graph.value.wires.splice(idx, 1)
		selectedWireId.value = undefined
		emitGraphUpdate()
		autoCompile()
	}
	if ((e.key === "Delete" || e.key === "Backspace") && selectedNodeId.value) {
		e.preventDefault()
		const nodeId = selectedNodeId.value
		if (nodeId && graph.value.nodes.find((n) => n.id === nodeId)?.defId !== "fragment_output") {
			graph.value.nodes = graph.value.nodes.filter((n) => n.id !== nodeId)
			graph.value.wires = graph.value.wires.filter((w) => w.fromNode !== nodeId && w.toNode !== nodeId)
			selectedNodeId.value = undefined
			emitGraphUpdate()
			autoCompile()
		}
	}
}

onMounted(() => {
	window.addEventListener("keydown", onKeyDown)
	autoCompile()
})
onUnmounted(() => {
	window.removeEventListener("keydown", onKeyDown)
	disposePreview()
})

// ─── Live Preview ────────────────────────────────────────────────────
let previewGl: WebGLRenderingContext | null = null
let previewProgram: WebGLProgram | null = null
let previewBuffer: WebGLBuffer | null = null
let previewCanvas: HTMLCanvasElement | null = null
let previewFrame = 0
let previewStartedAt = 0
const lastPreviewGlsl = ref("")

function updateLivePreview(glsl: string) {
	lastPreviewGlsl.value = glsl
	const canvas = livePreviewCanvas.value
	if (!canvas) return
	if (previewCanvas !== canvas) {
		disposePreview()
		previewCanvas = canvas
	}
	if (!previewGl) {
		previewGl = canvas.getContext("webgl", { alpha: true })
		if (!previewGl) {
			previewError.value = "WebGL preview is not available in this view."
			return
		}
		previewBuffer = previewGl.createBuffer()
		previewGl.bindBuffer(previewGl.ARRAY_BUFFER, previewBuffer)
		previewGl.bufferData(previewGl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, -1, 1, 1, -1, 1, 1]), previewGl.STATIC_DRAW)
	}
	try {
		const prog = compileProgram(previewGl, glsl)
		if (previewProgram) previewGl.deleteProgram(previewProgram)
		previewProgram = prog
		previewStartedAt = performance.now()
		previewError.value = ""
		cancelAnimationFrame(previewFrame)
		renderPreview()
	} catch (error) {
		previewError.value = error instanceof Error ? error.message : String(error)
	}
}

function disposePreview() {
	cancelAnimationFrame(previewFrame)
	if (previewGl) {
		if (previewProgram) previewGl.deleteProgram(previewProgram)
		if (previewBuffer) previewGl.deleteBuffer(previewBuffer)
	}
	previewGl = null
	previewProgram = null
	previewBuffer = null
	previewCanvas = null
}

watch(sidePanelTab, (tab) => {
	if (tab !== "preview") return
	nextTick(() => {
		if (lastPreviewGlsl.value) updateLivePreview(lastPreviewGlsl.value)
		else autoCompile()
	})
})

function renderPreview() {
	const gl = previewGl
	const prog = previewProgram
	const canvas = livePreviewCanvas.value
	if (!gl || !prog || !canvas) return
	gl.viewport(0, 0, canvas.width, canvas.height)
	gl.clearColor(0, 0, 0, 0)
	gl.clear(gl.COLOR_BUFFER_BIT)
	gl.useProgram(prog)
	const posLoc = gl.getAttribLocation(prog, "a_position")
	gl.enableVertexAttribArray(posLoc)
	gl.vertexAttribPointer(posLoc, 2, gl.FLOAT, false, 0, 0)
	gl.uniform2f(gl.getUniformLocation(prog, "u_resolution"), canvas.width, canvas.height)
	gl.uniform1f(gl.getUniformLocation(prog, "u_time"), (performance.now() - previewStartedAt) / 1000)
	gl.uniform3fv(gl.getUniformLocation(prog, "u_accent"), [0.57, 0.27, 1.0])
	gl.uniform3fv(gl.getUniformLocation(prog, "u_secondary"), [0, 0.82, 1.0])
	gl.uniform1f(gl.getUniformLocation(prog, "u_intensity"), 0.8)
	gl.uniform1f(gl.getUniformLocation(prog, "u_speed"), 1.0)
	gl.drawArrays(gl.TRIANGLES, 0, 6)
	previewFrame = requestAnimationFrame(renderPreview)
}

const vertexSrc = `attribute vec2 a_position; void main() { gl_Position = vec4(a_position, 0.0, 1.0); }`

function compileProgram(gl: WebGLRenderingContext, fragmentSrc: string): WebGLProgram {
	const vs = gl.createShader(gl.VERTEX_SHADER)!
	gl.shaderSource(vs, vertexSrc)
	gl.compileShader(vs)
	if (!gl.getShaderParameter(vs, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(vs) ?? "VS error")
	const fs = gl.createShader(gl.FRAGMENT_SHADER)!
	gl.shaderSource(fs, fragmentSrc)
	gl.compileShader(fs)
	if (!gl.getShaderParameter(fs, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(fs) ?? "FS error")
	const prog = gl.createProgram()!
	gl.attachShader(prog, vs)
	gl.attachShader(prog, fs)
	gl.linkProgram(prog)
	gl.deleteShader(vs)
	gl.deleteShader(fs)
	if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(prog) ?? "Link error")
	return prog
}

// ─── Utils ───────────────────────────────────────────────────────────
function bezier(x1: number, y1: number, x2: number, y2: number): string {
	const cp = Math.max(50, Math.abs(x2 - x1) * 0.4)
	return `M ${x1} ${y1} C ${x1 + cp} ${y1}, ${x2 - cp} ${y2}, ${x2} ${y2}`
}

function typeColor(type: GlslType): string {
	switch (type) {
		case "float": return "#4fc3f7"
		case "vec2": return "#7986cb"
		case "vec3": return "#81c784"
		case "vec4": return "#9575cd"
	}
}

function categoryColor(cat: string): string {
	switch (cat) {
		case "Input": return "#2e7d32"
		case "Math": return "#1565c0"
		case "Vector": return "#6a1b9a"
		case "Color": return "#c62828"
		case "Output": return "#e65100"
		default: return "#37474f"
	}
}
</script>

<style scoped>
.shader-graph {
	background: #0d0d0d;
	color: #e0e0e0;
	display: flex;
	flex-direction: column;
	height: 100%;
}

.shader-graph__toolbar {
	align-items: center;
	background: #1a1a1a;
	border-bottom: 1px solid #333;
	display: flex;
	gap: 1rem;
	justify-content: space-between;
	padding: 0.4rem 0.8rem;
}

.shader-graph__toolbar h3 {
	font-size: 0.95rem;
	font-weight: 600;
	margin: 0;
}

.shader-graph__toolbar-actions {
	display: flex;
	gap: 0.4rem;
}

.shader-graph__toolbar-actions button {
	background: #2a2a2a;
	border: 1px solid #444;
	border-radius: 4px;
	color: #ccc;
	cursor: pointer;
	font-size: 0.78rem;
	padding: 0.25rem 0.6rem;
}

.shader-graph__toolbar-actions button:hover {
	background: #3a3a3a;
}

.shader-graph__toolbar-actions button.active {
	background: #444;
	border-color: #7c4dff;
}

.shader-graph__body {
	display: flex;
	flex: 1;
	min-height: 0;
	position: relative;
}

.shader-graph__palette {
	background: #101010;
	border-right: 1px solid #333;
	display: flex;
	flex-direction: column;
	gap: 0.55rem;
	min-width: 220px;
	overflow: hidden;
	padding: 0.6rem;
	width: 240px;
}

.shader-graph__canvas {
	flex: 1;
	min-width: 0;
	overflow: hidden;
	position: relative;
}

.shader-graph__surface {
	position: relative;
	transform-origin: 0 0;
}

.shader-graph__wires {
	height: 100%;
	left: 0;
	pointer-events: none;
	position: absolute;
	top: 0;
	width: 100%;
}

.shader-graph__wire {
	fill: none;
	pointer-events: stroke;
	stroke-linecap: round;
	stroke-width: 2.5px;
	cursor: pointer;
}

.shader-graph__wire.selected {
	stroke-width: 4px;
	filter: drop-shadow(0 0 6px currentColor);
}

.shader-graph__wire--dragging {
	pointer-events: none;
	stroke-dasharray: 6 4;
}

.shader-graph__node {
	background: #1e1e1e;
	border: 2px solid #444;
	border-radius: 6px;
	cursor: grab;
	min-width: 180px;
	overflow: hidden;
	position: absolute;
	width: 180px;
}

.shader-graph__node.selected {
	border-color: #7c4dff;
	box-shadow: 0 0 12px rgb(124 77 255 / 0.3);
}

.shader-graph__node.output {
	border-color: #e65100;
}

.shader-graph__node-header {
	align-items: center;
	color: white;
	display: flex;
	font-size: 0.75rem;
	font-weight: 600;
	gap: 0.35rem;
	padding: 0.3rem 0.5rem;
}

.shader-graph__node-preview {
	border-bottom: 1px solid #333;
	display: block;
	height: 80px;
	width: 100%;
}

.shader-graph__ports {
	display: flex;
	justify-content: space-between;
	padding: 0.25rem 0;
}

.shader-graph__port-column {
	display: flex;
	flex-direction: column;
	gap: 2px;
}

.shader-graph__port {
	align-items: center;
	display: flex;
	font-size: 0.68rem;
	gap: 0.25rem;
	padding: 0 0.4rem;
}

.shader-graph__port--out {
	justify-content: flex-end;
}

.shader-graph__port-dot {
	border: 2px solid rgba(255, 255, 255, 0.3);
	border-radius: 50%;
	cursor: crosshair;
	flex-shrink: 0;
	height: 10px;
	transition: transform 0.1s;
	width: 10px;
}

.shader-graph__port-dot:hover {
	transform: scale(1.5);
	box-shadow: 0 0 6px 2px currentColor;
}

.shader-graph__port-name {
	color: #ccc;
}

.shader-graph__port-type {
	color: #777;
	font-family: monospace;
	font-size: 0.6rem;
}

.shader-graph__palette-search {
	align-items: center;
	background: var(--surface-a);
	border: 1px solid var(--surface-d);
	border-radius: 2px;
	display: grid;
	gap: 0.35rem;
	grid-template-columns: 1rem 1fr;
	padding: 0.35rem 0.45rem;
}

.shader-graph__palette-search input {
	background: transparent;
	border: 0;
	color: var(--text-color);
	min-width: 0;
	outline: 0;
}

.shader-graph__palette-list {
	flex: 1;
	max-height: 300px;
	overflow-y: auto;
}

.shader-graph__palette > .shader-graph__palette-list {
	max-height: none;
}

.shader-graph__palette-category {
	background: #222;
	color: #999;
	font-size: 0.65rem;
	font-weight: 700;
	padding: 0.25rem 0.5rem;
	text-transform: uppercase;
}

.shader-graph__palette-list button {
	align-items: center;
	background: transparent;
	border: 0;
	color: #ddd;
	cursor: pointer;
	display: flex;
	font-size: 0.78rem;
	gap: 0.4rem;
	padding: 0.35rem 0.6rem;
	width: 100%;
}

.shader-graph__palette-list button:hover {
	background: #2a2a2a;
}

.shader-graph__side-panel {
	background: #111;
	border-left: 1px solid #333;
	display: flex;
	flex-direction: column;
	min-width: 320px;
	overflow: hidden;
	width: 360px;
}

.shader-graph__tabs {
	background: #1a1a1a;
	border-bottom: 1px solid #333;
	display: flex;
	gap: 0.25rem;
	padding: 0.4rem;
}

.shader-graph__tabs button {
	background: transparent;
	border: 1px solid transparent;
	border-radius: 4px;
	color: #bbb;
	cursor: pointer;
	font-size: 0.72rem;
	padding: 0.3rem 0.45rem;
}

.shader-graph__tabs button.active,
.shader-graph__tabs button:hover {
	background: #2a2a2a;
	border-color: #444;
	color: #fff;
}

.shader-graph__code {
	display: flex;
	flex: 1;
	flex-direction: column;
	min-height: 0;
	overflow: hidden;
}

.shader-graph__code header {
	align-items: center;
	background: #1a1a1a;
	border-bottom: 1px solid #333;
	display: flex;
	justify-content: space-between;
	padding: 0.4rem 0.6rem;
}

.shader-graph__code header button {
	background: transparent;
	border: 0;
	color: #999;
	cursor: pointer;
}

.shader-graph__code pre {
	flex: 1;
	font-size: 0.72rem;
	margin: 0;
	overflow: auto;
	padding: 0.6rem;
	white-space: pre-wrap;
}

.shader-graph__code code {
	color: #81c784;
}

.shader-graph__errors {
	background: #111;
	flex: 1;
	overflow: auto;
	padding: 0.7rem;
}

.shader-graph__errors p {
	color: #ff6b6b;
	font-size: 0.75rem;
	margin: 0.15rem 0;
}

.shader-graph__preview-panel {
	background:
		linear-gradient(45deg, rgba(255, 255, 255, 0.05) 25%, transparent 25%),
		linear-gradient(-45deg, rgba(255, 255, 255, 0.05) 25%, transparent 25%),
		linear-gradient(45deg, transparent 75%, rgba(255, 255, 255, 0.05) 75%),
		linear-gradient(-45deg, transparent 75%, rgba(255, 255, 255, 0.05) 75%);
	background-color: #0b0b0b;
	background-position: 0 0, 0 8px, 8px -8px, -8px 0;
	background-size: 16px 16px;
	display: flex;
	flex-direction: column;
	gap: 0.6rem;
	padding: 0.7rem;
}

.shader-graph__live-preview {
	aspect-ratio: 16/9;
	background: #050505;
	border: 1px solid #333;
	display: block;
	width: 100%;
}

.shader-graph__preview-error {
	background: #2d1111;
	border: 1px solid #661111;
	border-radius: 4px;
	color: #ff9b9b;
	font-size: 0.75rem;
	margin: 0;
	padding: 0.5rem;
}

.shader-graph__preview-hint {
	background: #161616;
	border: 1px solid #333;
	border-radius: 4px;
	color: #aaa;
	font-size: 0.75rem;
	margin: 0;
	padding: 0.5rem;
}

.shader-graph__empty-state {
	color: #999 !important;
}
</style>
