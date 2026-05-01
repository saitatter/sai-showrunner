<template>
	<div class="overlay-editor" ref="editorDiv">
		<div class="overlay-editor-header">
			<div class="pt-4 px-1 flex flex-row w-full justify-content-center gap-1">
				<div ref="settingsMenuContainer">
					<p-button icon="mdi mdi-cog" @click="settingsMenuToggle" v-tooltip="'Overlay size settings'"></p-button>
				</div>
				<drop-down-panel
					v-model="settingsMenuOpen"
					:container="settingsMenuContainer"
					:style="{
						minWidth: '25rem',
						overflowY: 'auto',
					}"
				>
					<div class="p-1 py-2 flex flex-column gap-4" @mousedown="stopPropagation">
						<div class="overlay-size-presets">
							<button type="button" @click="applySizePreset(1920, 1080)">1080p</button>
							<button type="button" @click="applySizePreset(2560, 1440)">1440p</button>
							<button type="button" @click="applySizePreset(3840, 2160)">4K</button>
							<button type="button" @click="applySizePreset(1080, 1920)">Vertical</button>
						</div>
						<div class="flex flex-row gap-1">
							<div style="width: 0; flex: 1">
								<label-floater label="Width" v-slot="labelProps">
									<c-number-input
										v-model="model.size.width"
										v-bind="labelProps"
										suffix="px"
										local-path="size.width"
									/>
								</label-floater>
							</div>
							<div style="width: 0; flex: 1">
								<label-floater label="Height" v-slot="labelProps">
									<c-number-input
										class="number-fix"
										v-model="model.size.height"
										v-bind="labelProps"
										suffix="px"
										local-path="size.height"
									/>
								</label-floater>
							</div>
						</div>
					</div>
				</drop-down-panel>
				<div class="flex-grow-1">
					<data-input
						:schema="{ type: ResourceProxyFactory, resourceType: 'OBSConnection', name: `OBS Connection` }"
						v-model="view.obsId"
						local-path="obsId"
					/>
				</div>
				<div>
					<overlay-add-to-obs-button :obsId="view.obsId" :overlay-config="model" :overlay-id="overlayId" />
				</div>
				<div class="overlay-url">
					<label>Browser Source URL</label>
					<input :value="overlayUrl" readonly @focus="$event.target.select()" />
				</div>
				<div class="overlay-status">
					<span :class="{ dirty: document?.dirty }">
						<i :class="document?.dirty ? 'mdi mdi-circle-edit-outline' : 'mdi mdi-check-circle-outline'" />
						{{ document?.dirty ? "Unsaved changes" : "Saved" }}
					</span>
					<span :class="{ live: overlayPresence.connected, offline: !overlayPresence.connected }">
						<i :class="overlayPresence.connected ? 'mdi mdi-broadcast' : 'mdi mdi-broadcast-off'" />
						{{
							overlayPresence.connected
								? `Live preview connected (${overlayPresence.subscribers})`
								: "No live preview"
						}}
					</span>
				</div>
				<div>
					<p-button icon="mdi mdi-content-copy" @click="copyOverlayUrl" v-tooltip="'Copy Browser Source URL'"></p-button>
				</div>
				<div ref="previewMenuContainer">
					<p-button icon="mdi mdi-image-edit" @click="previewMenuToggle" v-tooltip="'Preview crop settings'" />
				</div>
				<drop-down-panel
					v-model="previewMenuOpen"
					:container="previewMenuContainer"
					:style="{
						minWidth: '25rem',
						overflowY: 'auto',
						maxHeight: '15rem',
					}"
				>
					<overlay-preview-menu v-model="model.preview" />
				</drop-down-panel>
				<div>
					<p-button
						icon="mdi mdi-open-in-app"
						@click="openOverlayDebug"
						v-tooltip="'Open in Browser'"
					></p-button>
				</div>
			</div>
		</div>
		<div class="flex flex-row flex-grow-1" ref="slideDiv">
			<overlay-edit-area v-model="model" v-model:view="view" style="flex: 1" />
			<expander-slider direction="vertical" invert v-model="splitterPos" :container="slideDiv" />
			<div class="overlay-properties" :style="{ width: `${splitterPos}px` }">
				<p-splitter layout="vertical" class="h-full">
					<p-splitter-panel>
						<overlay-widget-prop-edit class="h-full" v-model="model" />
					</p-splitter-panel>
					<p-splitter-panel>
						<overlay-widget-list class="h-full" v-model="model" />
					</p-splitter-panel>
				</p-splitter>
			</div>
		</div>
	</div>
</template>

<script setup lang="ts">
import { OverlayConfig } from "castmate-plugin-overlays-shared"
import { OverlayEditorView } from "./overlay-edit-types"
import {
	DataInput,
	ResourceProxyFactory,
	usePluginStore,
	DataBindingPath,
	useDocumentId,
	useDocument,
	useSettingValue,
	DropDownPanel,
	LabelFloater,
	stopPropagation,
	provideScrollAttachable,
	CNumberInput,
	ExpanderSlider,
	viewRef,
	useIpcCaller,
} from "castmate-ui-core"
import { computed, onBeforeUnmount, onMounted, ref, useModel, watch } from "vue"
import OverlayWidgetPropEdit from "./OverlayWidgetPropEdit.vue"
import OverlayWidgetList from "./OverlayWidgetList.vue"
import OverlayPreviewMenu from "./OverlayPreviewMenu.vue"
import OverlayAddToObsButton from "./OverlayAddToObsButton.vue"

import PSplitter from "primevue/splitter"
import PSplitterPanel from "primevue/splitterpanel"
import PCheckBox from "primevue/checkbox"
import PInputNumber from "primevue/inputnumber"
import PButton from "primevue/button"
import OverlayEditArea from "./OverlayEditArea.vue"

const props = defineProps<{
	modelValue: OverlayConfig
	view: OverlayEditorView
	pageData: { resourceId: string }
}>()

const overlayId = useDocumentId()
const document = useDocument(() => overlayId.value)

interface OverlayPresence {
	overlayId: string
	connected: boolean
	subscribers: number
}

const getOverlayPresence = useIpcCaller<(overlayId: string) => Promise<OverlayPresence>>("overlays", "getOverlayPresence")
const overlayPresence = ref<OverlayPresence>({
	overlayId: overlayId.value,
	connected: false,
	subscribers: 0,
})

const port = useSettingValue({ plugin: "castmate", setting: "port" })
const defaultObsSetting = useSettingValue({ plugin: "obs", setting: "obsDefault" })

const splitterPos = viewRef<number>("splitterPos", 350)

const editorDiv = ref<HTMLElement>()
const slideDiv = ref<HTMLElement>()

provideScrollAttachable(editorDiv)

const overlayUrl = computed(() => {
	return `http://localhost:${port.value ?? 8181}/overlays/${overlayId.value}`
})

let overlayPresenceTimer: ReturnType<typeof setInterval> | undefined

async function refreshOverlayPresence() {
	overlayPresence.value = await getOverlayPresence(overlayId.value)
}

function openOverlayDebug() {
	window.open(overlayUrl.value, "_blank")
}

async function copyOverlayUrl() {
	await navigator.clipboard.writeText(overlayUrl.value)
}

function applySizePreset(width: number, height: number) {
	model.value.size.width = width
	model.value.size.height = height
}

onMounted(() => {
	if (defaultObsSetting.value != null) {
		view.value.obsId = defaultObsSetting.value
	}

	void refreshOverlayPresence()
	overlayPresenceTimer = setInterval(() => void refreshOverlayPresence(), 2000)
})

onBeforeUnmount(() => {
	if (overlayPresenceTimer) {
		clearInterval(overlayPresenceTimer)
	}
})

const model = useModel(props, "modelValue")
const view = useModel(props, "view")

const previewMenuOpen = ref(false)
const previewMenuContainer = ref<HTMLElement>()

function previewMenuToggle(ev: MouseEvent) {
	if (!previewMenuOpen.value && model.value.preview == null) {
		console.log("Creating Whole Preview")
		model.value.preview = {
			offsetX: 0,
			offsetY: 0,
			source: undefined,
		}
	}

	previewMenuOpen.value = !previewMenuOpen.value
}

const settingsMenuContainer = ref<HTMLElement>()
const settingsMenuOpen = ref(false)
function settingsMenuToggle(ev: MouseEvent) {
	settingsMenuOpen.value = !settingsMenuOpen.value
}

onMounted(() => {
	watch(
		() => props.modelValue.preview,
		() => {
			console.log("Preview", props.modelValue.preview)
		},
		{ immediate: true, deep: true }
	)
})
</script>

<style scoped>
.overlay-editor-header {
	display: flex;
	flex-direction: row;
	min-height: 5rem;
	background-color: var(--surface-b);
}

.overlay-editor {
	display: flex;
	flex-direction: column;
}

.overlay-properties {
	background-color: var(--surface-b);
	user-select: none;
	width: 350px;
}

.overlay-size-presets {
	display: grid;
	gap: 0.5rem;
	grid-template-columns: repeat(4, minmax(0, 1fr));
}

.overlay-size-presets button {
	background: var(--surface-700);
	border: 1px solid var(--surface-600);
	border-radius: 4px;
	color: var(--text-color);
	cursor: pointer;
	padding: 0.45rem 0.55rem;
}

.overlay-url {
	display: grid;
	gap: 0.2rem;
	min-width: 18rem;
}

.overlay-url label {
	color: var(--text-color-secondary);
	font-size: 0.72rem;
	line-height: 1;
}

.overlay-url input {
	background: var(--surface-950);
	border: 1px solid var(--surface-700);
	border-radius: 4px;
	color: var(--text-color);
	font-size: 0.85rem;
	min-width: 0;
	padding: 0.45rem 0.55rem;
}

.overlay-status {
	display: grid;
	gap: 0.25rem;
	min-width: 10rem;
}

.overlay-status span {
	align-items: center;
	background: var(--surface-900);
	border: 1px solid var(--surface-700);
	border-radius: 999px;
	color: var(--text-color);
	display: flex;
	font-size: 0.75rem;
	gap: 0.35rem;
	padding: 0.3rem 0.55rem;
	white-space: nowrap;
}

.overlay-status span.dirty {
	background: color-mix(in srgb, #ffdf6b 14%, transparent);
	border-color: color-mix(in srgb, #ffdf6b 42%, var(--surface-700));
}

.overlay-status span.live {
	background: color-mix(in srgb, #54d98c 14%, transparent);
	border-color: color-mix(in srgb, #54d98c 42%, var(--surface-700));
}

.overlay-status span.offline {
	color: var(--text-color-secondary);
}

.number-fix :deep(.p-inputtext) {
	width: 100% !important;
}
</style>
