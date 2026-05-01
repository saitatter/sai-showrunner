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
					<h3>Local Shader Presets</h3>
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
import { useOverlayWidgets } from "castmate-overlay-widget-loader"
import { OverlayConfig } from "castmate-plugin-overlays-shared"
import {
	FlexScroller,
	DataInput,
	useDocumentSelection,
	useDataBinding,
	DataBindingPath,
	provideScrollAttachable,
} from "castmate-ui-core"
import { computed, onMounted, ref, useModel, watch } from "vue"
import OverlayWidgetTransformEdit from "./OverlayWidgetTransformEdit.vue"

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
	console.log(widgetSelection.value[0])
	return widgetSelection.value[0]
})

const widgets = useOverlayWidgets()
const SHADER_PRESETS_KEY = "showrunner.overlay.shaderPresets"
const shaderPresetName = ref("")
const shaderPresetNames = ref<string[]>([])

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

function readShaderPresets(): Record<string, string> {
	try {
		return JSON.parse(localStorage.getItem(SHADER_PRESETS_KEY) || "{}") as Record<string, string>
	} catch {
		return {}
	}
}

function writeShaderPresets(presets: Record<string, string>) {
	localStorage.setItem(SHADER_PRESETS_KEY, JSON.stringify(presets))
	shaderPresetNames.value = Object.keys(presets).sort((a, b) => a.localeCompare(b))
}

function refreshShaderPresets() {
	shaderPresetNames.value = Object.keys(readShaderPresets()).sort((a, b) => a.localeCompare(b))
}

function saveShaderPreset() {
	const name = shaderPresetName.value.trim()
	const source = String(selectedWidget.value?.config?.customFragmentShader || "").trim()
	if (!name || !source) return
	const presets = readShaderPresets()
	presets[name] = source
	writeShaderPresets(presets)
	shaderPresetName.value = ""
}

function applyShaderPreset(name: string) {
	const source = readShaderPresets()[name]
	if (!source || !selectedWidget.value) return
	selectedWidget.value.config.preset = "custom"
	selectedWidget.value.config.customFragmentShader = source
}

function deleteShaderPreset(name: string) {
	const presets = readShaderPresets()
	delete presets[name]
	writeShaderPresets(presets)
}

onMounted(refreshShaderPresets)
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
</style>
