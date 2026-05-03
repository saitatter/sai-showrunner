<template>
	<flex-scroller class="flex-grow-1 widget-props" inner-class="px-2" ref="scroller">
		<template v-if="selectedWidgetIndex != null && selectedWidgetInfo != null">
			<data-binding-path :local-path="`[${selectedWidgetIndex}]`">
				<data-input
					v-model="model.widgets[selectedWidgetIndex].config"
					:schema="selectedWidgetInfo.component.widget.config"
					local-path="config"
				/>
				<section v-if="isShaderLayer" class="shader-preset-panel">
					<h3>Shader Graph Editor</h3>
					<button type="button" class="shader-graph-open-btn" @click="shaderGraphOpen = true">
						<i class="mdi mdi-magic-staff" /> Open Shader Graph
					</button>
					<teleport to="body">
						<div v-if="shaderGraphOpen" class="shader-graph-overlay">
							<ShaderGraphEditor
								v-model="shaderGraph"
								@compile="onShaderGraphCompile"
							/>
							<button type="button" class="shader-graph-overlay__close" @click="shaderGraphOpen = false">
								<i class="mdi mdi-close" /> Close
							</button>
						</div>
					</teleport>
					<h3>Bundled Shader Presets</h3>
					<div class="shader-preset-panel__bundled">
						<button
							v-for="preset in bundledShaderPresets"
							:key="preset.id"
							type="button"
							:class="{ active: selectedWidget?.config?.preset === preset.id }"
							@click="applyBundledShaderPreset(preset.id)"
						>
							<span class="shader-preset-panel__preview" :class="`preset-${preset.id}`" />
							<span>
								<strong>{{ preset.name }}</strong>
								<small>{{ preset.description }}</small>
							</span>
						</button>
					</div>
					<h3>Local Shader Presets</h3>
					<p v-if="shaderPresetHint" class="shader-preset-panel__hint">{{ shaderPresetHint }}</p>
					<div class="shader-preset-panel__save">
						<input v-model="shaderPresetName" type="text" placeholder="Preset name" />
						<button type="button" @click="saveShaderPreset">Save Preset</button>
					</div>
					<p v-if="!shaderPresetNames.length" class="shader-preset-panel__muted">No local shader presets saved yet.</p>
					<div v-else class="shader-preset-panel__list">
						<button v-for="name in shaderPresetNames" :key="name" type="button" @click="applyShaderPreset(name)">
							<i class="mdi mdi-magic-staff" />
							{{ name }}
						</button>
						<button v-for="name in shaderPresetNames" :key="`${name}:delete`" type="button" class="danger" @click="deleteShaderPreset(name)">
							<i class="mdi mdi-delete-outline" />
							{{ name }}
						</button>
					</div>
				</section>
				<overlay-widget-transform-edit v-model="model.widgets[selectedWidgetIndex]" />
			</data-binding-path>
		</template>
	</flex-scroller>
</template>

<script setup lang="ts">
import { useOverlayWidgets } from "showrunner-overlay-widget-loader"
import { OverlayConfig } from "showrunner-plugin-overlays-shared"
import {
	FlexScroller,
	DataInput,
	useDocumentSelection,
	useDataBinding,
	DataBindingPath,
	provideScrollAttachable,
	useIpcCaller,
} from "showrunner-ui-core"
import { computed, onMounted, ref, useModel, watch } from "vue"
import OverlayWidgetTransformEdit from "./OverlayWidgetTransformEdit.vue"
import ShaderGraphEditor from "./shader-graph/ShaderGraphEditor.vue"
import type { ShaderGraph } from "./shader-graph/shader-nodes"
import { useConfirm } from "primevue/useconfirm"

const props = defineProps<{
	modelValue: OverlayConfig
}>()

const model = useModel(props, "modelValue")

useDataBinding("widgets")

const scroller = ref<InstanceType<typeof FlexScroller>>()
provideScrollAttachable(() => scroller.value?.scroller ?? undefined)

const widgetSelection = useDocumentSelection()

const selectedWidgetId = computed(() => {
	if (widgetSelection.value.length > 1 || widgetSelection.value.length == 0) return undefined
	return widgetSelection.value[0]
})

const widgets = useOverlayWidgets()
const bundledShaderPresets = [
	{ id: "aurora", name: "Aurora", description: "Soft waves for scene mood." },
	{ id: "grid", name: "Grid", description: "Motion grid for tech overlays." },
	{ id: "plasma", name: "Plasma", description: "High energy color field." },
	{ id: "nebula", name: "Nebula", description: "Cloudy procedural depth." },
	{ id: "scanlines", name: "Scanlines", description: "CRT-style sweep bands." },
	{ id: "vortex", name: "Vortex", description: "Circular portal motion." },
]
const shaderPresetName = ref("")
const shaderPresetNames = ref<string[]>([])
const shaderPresets = ref<Record<string, string>>({})
const listShaderPresets = useIpcCaller<() => Promise<Record<string, string>>>("overlays", "listShaderPresets")
const saveShaderPresetCall = useIpcCaller<(preset: { name: string; source: string }) => Promise<Record<string, string>>>("overlays", "saveShaderPreset")
const deleteShaderPresetCall = useIpcCaller<(name: string) => Promise<Record<string, string>>>("overlays", "deleteShaderPreset")

const selectedWidgetIndex = computed(() => {
	if (!selectedWidgetId.value) return

	const idx = props.modelValue.widgets.findIndex((w) => w.id == selectedWidgetId.value)
	if (idx < 0) return undefined

	return idx
})

const selectedWidgetInfo = computed(() => {
	if (selectedWidgetIndex.value === undefined) return undefined

	const widget = props.modelValue.widgets[selectedWidgetIndex.value]

	return widgets.getWidget(widget.plugin, widget.widget)
})

const selectedWidget = computed(() => {
	if (selectedWidgetIndex.value === undefined) return undefined
	return model.value.widgets[selectedWidgetIndex.value]
})

const isShaderLayer = computed(() => selectedWidget.value?.plugin === "overlays" && selectedWidget.value?.widget === "shaderLayer")
const shaderPresetHint = computed(() => {
	if (!isShaderLayer.value) return ""
	if (selectedWidget.value?.config?.preset === "custom" && !String(selectedWidget.value?.config?.customFragmentShader || "").trim()) {
		return "Custom preset is selected but the shader source is empty."
	}
	return ""
})

function setShaderPresets(presets: Record<string, string>) {
	shaderPresets.value = presets
	shaderPresetNames.value = Object.keys(presets).sort((a, b) => a.localeCompare(b))
}

async function refreshShaderPresets() {
	setShaderPresets(await listShaderPresets())
}

async function saveShaderPreset() {
	const name = shaderPresetName.value.trim()
	const source = String(selectedWidget.value?.config?.customFragmentShader || "").trim()
	if (!name || !source) return
	setShaderPresets(await saveShaderPresetCall({ name, source }))
	shaderPresetName.value = ""
}

function applyBundledShaderPreset(name: string) {
	if (!selectedWidget.value) return
	selectedWidget.value.config.preset = name
}

function applyShaderPreset(name: string) {
	const source = shaderPresets.value[name]
	if (!source || !selectedWidget.value) return
	selectedWidget.value.config.preset = "custom"
	selectedWidget.value.config.customFragmentShader = source
}

const confirm = useConfirm()

function deleteShaderPreset(name: string) {
	confirm.require({
		header: `Delete Shader Preset?`,
		message: `Are you sure you want to delete the shader preset "${name}"? This cannot be undone.`,
		icon: "mdi mdi-delete",
		async accept() {
			setShaderPresets(await deleteShaderPresetCall(name))
		},
	})
}

onMounted(refreshShaderPresets)

// ── Shader Graph Editor ──
const shaderGraphOpen = ref(false)
const shaderGraph = ref<ShaderGraph>({
	nodes: [
		{ id: "output", defId: "fragment_output", x: 600, y: 200 },
		{ id: "uv", defId: "uv", x: 50, y: 200 },
	],
	wires: [],
})

function onShaderGraphCompile(glsl: string) {
	if (!selectedWidget.value) return
	selectedWidget.value.config.preset = "custom"
	selectedWidget.value.config.customFragmentShader = glsl
}
</script>

<style scoped>
.widget-props {
	min-height: 5rem;
}

.shader-preset-panel {
	background: var(--surface-900);
	border: 1px solid var(--surface-700);
	border-radius: 6px;
	display: grid;
	gap: 0.55rem;
	margin: 0.75rem 0;
	padding: 0.75rem;
}

.shader-preset-panel h3 {
	font-size: 0.9rem;
	margin: 0;
}

.shader-preset-panel__bundled {
	display: grid;
	gap: 0.45rem;
	grid-template-columns: repeat(auto-fit, minmax(11rem, 1fr));
}

.shader-preset-panel__bundled button {
	justify-content: flex-start;
	min-height: 4.4rem;
	text-align: left;
}

.shader-preset-panel__bundled button.active {
	border-color: #e9aaff;
	box-shadow: 0 0 0 1px rgba(233, 170, 255, 0.35);
}

.shader-preset-panel__bundled strong,
.shader-preset-panel__bundled small {
	display: block;
}

.shader-preset-panel__bundled small {
	color: var(--text-color-secondary);
	font-size: 0.72rem;
}

.shader-preset-panel__preview {
	border-radius: 4px;
	display: block;
	flex: 0 0 2.2rem;
	height: 2.2rem;
}

.shader-preset-panel__preview.preset-aurora {
	background: linear-gradient(135deg, #00d1ff, #9146ff 55%, #f0a6ff);
}

.shader-preset-panel__preview.preset-grid {
	background:
		linear-gradient(90deg, rgba(255, 255, 255, 0.25) 1px, transparent 1px),
		linear-gradient(rgba(255, 255, 255, 0.25) 1px, transparent 1px),
		#1b1238;
	background-size: 8px 8px;
}

.shader-preset-panel__preview.preset-plasma {
	background: radial-gradient(circle at 35% 30%, #e9aaff, transparent 30%), radial-gradient(circle at 65% 60%, #00d1ff, #3b1974);
}

.shader-preset-panel__preview.preset-nebula {
	background: radial-gradient(circle at 30% 35%, #9146ff, transparent 35%), radial-gradient(circle at 70% 65%, #00d1ff, #160b28);
}

.shader-preset-panel__preview.preset-scanlines {
	background: repeating-linear-gradient(0deg, #141414, #141414 4px, #9be7ff 5px, #141414 7px);
}

.shader-preset-panel__preview.preset-vortex {
	background: conic-gradient(from 45deg, #00d1ff, #9146ff, #111, #00d1ff);
}

.shader-preset-panel__save,
.shader-preset-panel__list {
	display: grid;
	gap: 0.4rem;
	grid-template-columns: 1fr auto;
}

.shader-preset-panel input {
	background: var(--surface-950);
	border: 1px solid var(--surface-700);
	border-radius: 4px;
	color: var(--text-color);
	padding: 0.45rem 0.55rem;
}

.shader-preset-panel button {
	align-items: center;
	background: var(--surface-700);
	border: 1px solid var(--surface-600);
	border-radius: 4px;
	color: var(--text-color);
	cursor: pointer;
	display: flex;
	gap: 0.35rem;
	justify-content: center;
	padding: 0.45rem 0.55rem;
}

.shader-preset-panel button.danger {
	border-color: #8d3144;
	color: #ff9aad;
}

.shader-preset-panel__muted {
	color: var(--text-color-secondary);
	font-size: 0.8rem;
	margin: 0;
}

.shader-preset-panel__hint {
	background: rgba(255, 210, 112, 0.12);
	border: 1px solid rgba(255, 210, 112, 0.35);
	border-radius: 4px;
	color: #ffd270;
	font-size: 0.8rem;
	margin: 0;
	padding: 0.45rem 0.55rem;
}

.shader-graph-open-btn {
	background: linear-gradient(135deg, #7c4dff, #00d1ff) !important;
	border-color: #9b7dff !important;
	color: #fff !important;
	font-weight: 600;
	padding: 0.55rem 0.75rem !important;
}

.shader-graph-open-btn:hover {
	filter: brightness(1.15);
}
</style>

<style>
.shader-graph-overlay {
	background: #0d0d0d;
	display: flex;
	flex-direction: column;
	inset: 0;
	position: fixed;
	z-index: 1000;
}

.shader-graph-overlay__close {
	align-items: center;
	background: #333;
	border: 1px solid #555;
	border-radius: 4px;
	color: #eee;
	cursor: pointer;
	display: flex;
	font-size: 0.85rem;
	gap: 0.3rem;
	padding: 0.35rem 0.65rem;
	position: absolute;
	right: 0.8rem;
	top: 0.4rem;
	z-index: 10;
}

.shader-graph-overlay__close:hover {
	background: #555;
}
</style>
