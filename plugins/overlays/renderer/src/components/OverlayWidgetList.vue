<template>
	<div class="flex flex-column widget-list">
		<div class="flex-grow-1 widget-list-container">
			<flex-scroller class="h-full" inner-class="flex flex-column gap-1">
				<draggable-collection
					v-model="model.widgets"
					data-type="overlay-widgets"
					key-prop="id"
					handle-class="drag-handle"
					local-path="widgets"
					style="gap: 0.25rem"
				>
					<template #no-items></template>
					<template #item="{ item, index }">
						<overlay-widget-list-item
							v-model="model.widgets[index]"
							:selected="selection.includes(item.id)"
							@click="widgetClick(index, $event)"
							@delete="deleteWidget(index)"
							:local-path="`[${index}]`"
							:presence="widgetPresenceById.get(item.id)"
						/>
					</template>
				</draggable-collection>
			</flex-scroller>
		</div>
		<div class="flex flex-row px-2 pb-2">
			<p-button icon="mdi mdi-plus" @click="popAddMenu" class="extra-small-button" size="small" v-tooltip="'Add widget'" />
			<p-menu :model="addMenuItems" ref="addMenu" :popup="true" />
		</div>
		<div class="browser-source-card">
			<div>
				<span>OBS Browser Source</span>
				<input :value="overlayUrl" readonly @focus="$event.target.select()" />
				<small :class="{ live: overlayPresence.connected }">
					<i :class="overlayPresence.connected ? 'mdi mdi-broadcast' : 'mdi mdi-broadcast-off'" />
					{{ overlayPresence.connected ? `Connected (${overlayPresence.subscribers})` : "Disconnected" }}
				</small>
				<p v-if="!overlayPresence.connected" class="browser-source-card__hint">
					OBS is not connected to this overlay yet. Copy this URL into an OBS Browser Source to make Chat Feed,
					Paid Alert, Scene Banner, and Shader Layer widgets go live.
				</p>
			</div>
			<div class="browser-source-card__actions">
				<button type="button" @click="copyOverlayUrl" v-tooltip="'Copy Browser Source URL'">
					<i class="mdi mdi-content-copy" />
					Copy
				</button>
				<button type="button" @click="openOverlayUrl" v-tooltip="'Open Browser Source URL'">
					<i class="mdi mdi-open-in-app" />
					Open
				</button>
			</div>
		</div>
		<div class="quick-labels">
			<button type="button" @click="addLabelTemplate('YouTube Latest', '{{ youtube.latestMessage.message }}')" v-tooltip="'Add a label bound to the latest YouTube chat message'">
				<i class="mdi mdi-youtube" />
				YouTube Latest
			</button>
			<button type="button" @click="addLabelTemplate('Twitch Channel', '{{ twitch.channel.displayName }}')" v-tooltip="'Add a label bound to Twitch channel state'">
				<i class="mdi mdi-twitch" />
				Twitch Channel
			</button>
			<button type="button" @click="addLabelTemplate('Stream Status', '{{ youtube.broadcast.status }}')" v-tooltip="'Add a label bound to stream status'">
				<i class="mdi mdi-broadcast" />
				Stream Status
			</button>
		</div>
	</div>
</template>

<script setup lang="ts">
import { OverlayConfig } from "ShowRunner-plugin-overlays-shared"
import {
	useDocumentSelection,
	FlexScroller,
	usePropagationStop,
	useCommitUndo,
	DataBindingPath,
	DraggableCollection,
	useDocumentId,
	useSettingValue,
	useIpcCaller,
} from "ShowRunner-ui-core"
import { computed, onBeforeUnmount, onMounted, ref, useModel } from "vue"
import PButton from "primevue/button"
import PMenu from "primevue/menu"
import { OverlayWidgetInfo, useOverlayWidgets } from "ShowRunner-overlay-widget-loader"
import type { MenuItem } from "primevue/menuitem"
import { nanoid } from "nanoid/non-secure"
import { constructDefault } from "ShowRunner-schema"
import _cloneDeep from "lodash/cloneDeep"
import OverlayWidgetListItem from "./OverlayWidgetListItem.vue"

const props = defineProps<{
	modelValue: OverlayConfig
}>()

const model = useModel(props, "modelValue")

const selection = useDocumentSelection("widgets")

const overlayWidgets = useOverlayWidgets()

const commitUndo = useCommitUndo()
const overlayId = useDocumentId()
const port = useSettingValue({ plugin: "ShowRunner", setting: "port" })
const overlayUrl = computed(() => `http://localhost:${port.value ?? 8181}/overlays/${overlayId.value}`)

interface OverlayPresence {
	overlayId: string
	connected: boolean
	subscribers: number
	widgets: OverlayWidgetPresence[]
}

interface OverlayWidgetPresence {
	id: string
	name: string
	plugin: string
	widget: string
	visible: boolean
	connected: boolean
	subscribers: number
}

const getOverlayPresence = useIpcCaller<(overlayId: string) => Promise<OverlayPresence>>("overlays", "getOverlayPresence")
const overlayPresence = ref<OverlayPresence>({ overlayId: overlayId.value, connected: false, subscribers: 0, widgets: [] })
let overlayPresenceTimer: ReturnType<typeof setInterval> | undefined

const widgetPresenceById = computed(() => new Map(overlayPresence.value.widgets.map((widget) => [widget.id, widget])))

async function refreshOverlayPresence() {
	try {
		overlayPresence.value = await getOverlayPresence(overlayId.value)
	} catch {
		overlayPresence.value = {
			overlayId: overlayId.value,
			connected: false,
			subscribers: 0,
			widgets: model.value.widgets.map((widget) => ({
				id: widget.id,
				name: widget.name,
				plugin: widget.plugin,
				widget: widget.widget,
				visible: widget.visible,
				connected: false,
				subscribers: 0,
			})),
		}
	}
}

async function addWidget(widget: OverlayWidgetInfo) {
	const size = {
		width:
			widget.component.widget.defaultSize.width == "canvas"
				? props.modelValue.size.width
				: widget.component.widget.defaultSize.width,
		height:
			widget.component.widget.defaultSize.height == "canvas"
				? props.modelValue.size.height
				: widget.component.widget.defaultSize.height,
	}

	let name = widget.component.widget.name
	let number = 1

	while (model.value.widgets.find((w) => w.name == name)) {
		name = `${widget.component.widget.name} ${number}`
		number++
	}

	model.value.widgets.push({
		id: nanoid(),
		plugin: widget.plugin,
		widget: widget.component.widget.id,
		config: await constructDefault(widget.component.widget.config),
		size,
		position: {
			x: 0,
			y: 0,
		},
		name,
		visible: true,
		locked: false,
	})

	commitUndo()
}

async function addLabelTemplate(name: string, message: string) {
	const labelWidget = overlayWidgets.widgets.find((widget) => widget.plugin === "overlays" && widget.component.widget.id === "label")
	if (!labelWidget) return

	const config = await constructDefault(labelWidget.component.widget.config)
	config.message = message

	model.value.widgets.push({
		id: nanoid(),
		plugin: labelWidget.plugin,
		widget: labelWidget.component.widget.id,
		config,
		size: {
			width: 420,
			height: 90,
		},
		position: {
			x: 64,
			y: 64 + model.value.widgets.length * 18,
		},
		name,
		visible: true,
		locked: false,
	})

	commitUndo()
}

const addMenu = ref<InstanceType<typeof PMenu>>()
const addMenuItems = computed<MenuItem[]>(() => {
	return overlayWidgets.widgets.map((w) => {
		return {
			label: w.component.widget.name,
			icon: w.component.widget.icon,
			command() {
				addWidget(w)
			},
		}
	})
})

function popAddMenu(ev: MouseEvent) {
	addMenu.value?.toggle(ev)
}

const stopPropagation = usePropagationStop()

function widgetClick(idx: number, ev: MouseEvent) {
	if (ev.button != 0) return

	const id = props.modelValue.widgets[idx].id

	if (ev.ctrlKey) {
		const selIdx = selection.value.findIndex((s) => s == id)
		if (selIdx >= 0) {
			selection.value.splice(selIdx, 1)
		} else {
			selection.value.push(id)
		}
	} else {
		selection.value = [id]
		stopPropagation(ev)
	}
}

async function copyOverlayUrl() {
	await navigator.clipboard.writeText(overlayUrl.value)
}

function openOverlayUrl() {
	window.open(overlayUrl.value, "_blank")
}

function deleteWidget(idx: number) {
	model.value.widgets.splice(idx, 1)
	commitUndo()
}

onMounted(() => {
	void refreshOverlayPresence()
	overlayPresenceTimer = setInterval(() => void refreshOverlayPresence(), 2500)
})

onBeforeUnmount(() => {
	if (overlayPresenceTimer) clearInterval(overlayPresenceTimer)
})
</script>

<style scoped>
.widget-list {
	min-height: 5rem;
}

.widget-list-container {
	padding: 0.5rem 0;
	margin: 0.5rem;
	border: solid 1px var(--surface-border);
	border-radius: var(--border-radius);
}

.widget-list-item {
	display: flex;
	flex-direction: row;
	align-items: center;
	padding: 0 0.5rem;
}

.widget-list-item.selected {
	background-color: rgba(96, 165, 250, 0.16);
}

.quick-labels {
	border-top: 1px solid var(--surface-border);
	display: grid;
	gap: 0.4rem;
	padding: 0.5rem;
}

.browser-source-card {
	border-top: 1px solid var(--surface-border);
	display: grid;
	gap: 0.5rem;
	padding: 0.5rem;
}

.browser-source-card span {
	color: var(--text-color-secondary);
	display: block;
	font-size: 0.72rem;
	margin-bottom: 0.25rem;
}

.browser-source-card input {
	background: var(--surface-950);
	border: 1px solid var(--surface-700);
	border-radius: 4px;
	color: var(--text-color);
	font-size: 0.78rem;
	padding: 0.45rem 0.55rem;
	width: 100%;
}

.browser-source-card small {
	align-items: center;
	color: var(--text-color-secondary);
	display: flex;
	font-size: 0.75rem;
	gap: 0.35rem;
	margin-top: 0.25rem;
}

.browser-source-card small.live {
	color: #54d98c;
}

.browser-source-card__hint {
	background: color-mix(in srgb, #ffdf6b 12%, transparent);
	border: 1px solid color-mix(in srgb, #ffdf6b 38%, var(--surface-700));
	border-radius: 4px;
	color: var(--text-color);
	font-size: 0.75rem;
	line-height: 1.35;
	margin: 0.45rem 0 0;
	padding: 0.45rem 0.55rem;
}

.browser-source-card__actions {
	display: grid;
	gap: 0.4rem;
	grid-template-columns: 1fr 1fr;
}

.quick-labels button,
.browser-source-card__actions button {
	align-items: center;
	background: var(--surface-900);
	border: 1px solid var(--surface-700);
	border-radius: 4px;
	color: var(--text-color);
	cursor: pointer;
	display: flex;
	gap: 0.45rem;
	padding: 0.45rem 0.55rem;
	text-align: left;
}
</style>
