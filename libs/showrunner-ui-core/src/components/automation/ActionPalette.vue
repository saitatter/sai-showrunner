<template>
	<div
		v-if="openState"
		ref="menuRef"
		class="automation-command-menu"
		:style="{ left: `${position.x}px`, top: `${position.y}px` }"
		@click.stop
		@pointerdown.stop
		@mousedown.stop
		@contextmenu.prevent.stop
	>
		<header class="automation-command-menu__header">
			<div>
				<strong>Command Menu</strong>
				<span>{{ includeTriggers ? "Choose a trigger or action" : "Choose an action" }}</span>
			</div>
			<button type="button" aria-label="Close menu" @click="close">
				<i class="mdi mdi-close" />
			</button>
		</header>

		<label class="automation-command-menu__search">
			<i class="mdi mdi-magnify" />
			<input ref="searchRef" v-model="query" type="search" placeholder="Search triggers or actions..." />
		</label>

		<div v-if="search && disabledMatchesCount > 0" class="automation-command-menu__disabled-hint">
			<i class="mdi mdi-eye-off-outline" />
			<span>{{ disabledMatchesCount }} result{{ disabledMatchesCount > 1 ? 's' : '' }} in disabled integrations</span>
		</div>

		<section v-if="includeTriggers" class="automation-command-menu__section">
			<button type="button" class="automation-command-menu__section-header" :aria-expanded="isGroupOpen('triggers')" @click="toggleGroup('triggers')">
				<span><i class="mdi mdi-flash" /> Triggers</span>
				<i :class="isGroupOpen('triggers') ? 'mdi mdi-chevron-up' : 'mdi mdi-chevron-down'" />
			</button>
			<div v-if="isGroupOpen('triggers')" class="automation-command-menu__groups">
				<div v-for="group in triggerGroups" :key="group.id" class="automation-command-menu__group">
					<button type="button" class="automation-command-menu__group-header" :aria-expanded="isGroupOpen(`trigger:${group.id}`)" @click="toggleGroup(`trigger:${group.id}`)">
						<span>
							<i :class="group.icon" :style="{ color: group.color }" />
							{{ group.name }}
						</span>
						<i :class="isGroupOpen(`trigger:${group.id}`) ? 'mdi mdi-chevron-up' : 'mdi mdi-chevron-down'" />
					</button>
					<div v-if="isGroupOpen(`trigger:${group.id}`)" class="automation-command-menu__items">
						<button v-for="item in group.items" :key="item.key" type="button" @click="selectTrigger(item.key)">
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

		<section class="automation-command-menu__section">
			<button type="button" class="automation-command-menu__section-header" :aria-expanded="isGroupOpen('actions')" @click="toggleGroup('actions')">
				<span><i class="mdi mdi-play-circle-outline" /> Actions</span>
				<i :class="isGroupOpen('actions') ? 'mdi mdi-chevron-up' : 'mdi mdi-chevron-down'" />
			</button>
			<div v-if="isGroupOpen('actions')" class="automation-command-menu__groups">
				<div v-for="group in actionGroups" :key="group.id" class="automation-command-menu__group">
					<button type="button" class="automation-command-menu__group-header" :aria-expanded="isGroupOpen(`action:${group.id}`)" @click="toggleGroup(`action:${group.id}`)">
						<span>
							<i :class="group.icon" :style="{ color: group.color }" />
							{{ group.name }}
						</span>
						<i :class="isGroupOpen(`action:${group.id}`) ? 'mdi mdi-chevron-up' : 'mdi mdi-chevron-down'" />
					</button>
					<div v-if="isGroupOpen(`action:${group.id}`)" class="automation-command-menu__items">
						<button v-for="item in group.items" :key="item.key" type="button" @click="selectAction(item.key)">
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
</template>

<script setup lang="ts">
import { computed, nextTick, onMounted, onUnmounted, ref } from "vue"
import { ActionSelection, TriggerSelection, usePluginStore } from "../../main"

interface CommandMenuItem {
	key: string
	pluginId: string
	pluginName: string
	name: string
	icon: string
	color: string
	searchText: string
}

interface CommandMenuGroup {
	id: string
	name: string
	icon: string
	color: string
	items: CommandMenuItem[]
}

withDefaults(
	defineProps<{
		appendTo?: string
		includeTriggers?: boolean
	}>(),
	{
		appendTo: "body",
		includeTriggers: false,
	}
)

const emit = defineEmits<{
	selectAction: [selection: ActionSelection]
	selectTrigger: [selection: TriggerSelection]
}>()

const pluginStore = usePluginStore()
const menuRef = ref<HTMLElement>()
const searchRef = ref<HTMLInputElement>()
const openState = ref(false)
const position = ref({ x: 0, y: 0 })
const query = ref("")
const openGroups = ref<Record<string, boolean>>({
	actions: true,
	triggers: true,
})

const search = computed(() => query.value.trim().toLowerCase())
const actionGroups = computed(() => buildGroups("actions", (plugin) => plugin.actions, (entry) => entry.icon || "mdi mdi-play"))
const triggerGroups = computed(() => buildGroups("triggers", (plugin) => plugin.triggers, (entry) => entry.icon || "mdi mdi-flash"))

const disabledMatchesCount = computed(() => {
	if (!search.value) return 0
	let count = 0
	for (const plugin of pluginStore.pluginMap.values()) {
		if (pluginStore.isPluginEnabled(plugin.id)) continue
		const actions = Object.values(plugin.actions || {})
		const triggers = props.includeTriggers ? Object.values(plugin.triggers || {}) : []
		for (const entry of [...actions, ...triggers]) {
			const searchText = `${plugin.id} ${plugin.name} ${(entry as any).id} ${(entry as any).name}`.toLowerCase()
			if (searchText.includes(search.value)) count++
		}
	}
	return count
})

function buildGroups<TEntry extends { id: string; name: string; icon?: string; color?: string }>(
	kind: "actions" | "triggers",
	getEntries: (plugin: any) => Record<string, TEntry>,
	getIcon: (entry: TEntry) => string
) {
	return [...pluginStore.pluginMap.values()]
		.filter((plugin) => pluginStore.isPluginEnabled(plugin.id))
		.map<CommandMenuGroup>((plugin) => ({
			id: plugin.id,
			name: plugin.name,
			icon: plugin.icon,
			color: plugin.color,
			items: Object.values(getEntries(plugin))
				.map((entry) => ({
					key: `${plugin.id}:${entry.id}`,
					pluginId: plugin.id,
					pluginName: plugin.name,
					name: entry.name,
					icon: getIcon(entry),
					color: entry.color || plugin.color,
					searchText: `${kind} ${plugin.id} ${plugin.name} ${entry.id} ${entry.name}`.toLowerCase(),
				}))
				.filter((entry) => !search.value || entry.searchText.includes(search.value))
				.sort((a, b) => a.name.localeCompare(b.name)),
		}))
		.filter((group) => group.items.length || group.name.toLowerCase().includes(search.value))
		.sort((a, b) => a.name.localeCompare(b.name))
}

function parseSelection(value: string) {
	const [plugin, id] = value.split(":")
	if (!plugin || !id) return undefined
	return { plugin, id }
}

function selectAction(key: string) {
	const selection = parseSelection(key)
	if (!selection) return
	emit("selectAction", { plugin: selection.plugin, action: selection.id })
	close()
}

function selectTrigger(key: string) {
	const selection = parseSelection(key)
	if (!selection) return
	emit("selectTrigger", { plugin: selection.plugin, trigger: selection.id })
	close()
}

function toggleGroup(key: string) {
	openGroups.value[key] = !isGroupOpen(key)
}

function isGroupOpen(key: string) {
	return openGroups.value[key] ?? true
}

function close() {
	openState.value = false
}

function onWindowPointerDown(event: PointerEvent) {
	if (!openState.value) return
	if (menuRef.value?.contains(event.target as Node)) return
	close()
}

function onWindowKeyDown(event: KeyboardEvent) {
	if (event.key === "Escape" && openState.value) {
		event.preventDefault()
		close()
	}
}

onMounted(() => {
	window.addEventListener("pointerdown", onWindowPointerDown)
	window.addEventListener("keydown", onWindowKeyDown)
})

onUnmounted(() => {
	window.removeEventListener("pointerdown", onWindowPointerDown)
	window.removeEventListener("keydown", onWindowKeyDown)
})

defineExpose({
	open(event: MouseEvent) {
		const menuWidth = 360
		const menuHeight = 560
		position.value = {
			x: Math.max(8, Math.min(event.clientX, window.innerWidth - menuWidth - 8)),
			y: Math.max(8, Math.min(event.clientY, window.innerHeight - menuHeight - 8)),
		}
		query.value = ""
		openState.value = true
		void nextTick(() => searchRef.value?.focus())
	},
	close,
})
</script>

<style scoped>
.automation-command-menu {
	background: var(--surface-b);
	border: 1px solid var(--surface-d);
	border-radius: 3px;
	box-shadow: 0 18px 45px rgb(0 0 0 / 0.42);
	color: var(--text-color);
	display: grid;
	gap: 0.35rem;
	max-height: min(35rem, calc(100vh - 1rem));
	overflow: auto;
	padding: 0.35rem;
	position: fixed;
	width: 360px;
	z-index: 1000;
}

.automation-command-menu__header {
	align-items: center;
	background: var(--surface-c);
	border: 1px solid var(--surface-d);
	border-radius: 2px;
	display: flex;
	justify-content: space-between;
	padding: 0.5rem 0.55rem;
}

.automation-command-menu__disabled-hint {
	align-items: center;
	background: rgba(255, 152, 0, 0.12);
	border: 1px solid rgba(255, 152, 0, 0.3);
	border-radius: 2px;
	color: #ffa726;
	display: flex;
	gap: 0.4rem;
	font-size: 0.78rem;
	padding: 0.35rem 0.55rem;
}

.automation-command-menu__header div {
	display: grid;
	gap: 0.1rem;
	min-width: 0;
}

.automation-command-menu__header span {
	color: var(--text-color-secondary);
	font-size: 0.75rem;
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.automation-command-menu__header button {
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

.automation-command-menu__search {
	align-items: center;
	background: var(--surface-a);
	border: 1px solid var(--surface-d);
	border-radius: 2px;
	display: grid;
	gap: 0.35rem;
	grid-template-columns: 1rem 1fr;
	padding: 0.35rem 0.45rem;
}

.automation-command-menu__search input {
	background: transparent;
	border: 0;
	color: var(--text-color);
	min-width: 0;
	outline: 0;
}

.automation-command-menu__section {
	border: 1px solid var(--surface-d);
	border-radius: 2px;
	overflow: hidden;
}

.automation-command-menu__section-header,
.automation-command-menu__group-header {
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

.automation-command-menu__section-header span,
.automation-command-menu__group-header span {
	align-items: center;
	display: flex;
	gap: 0.4rem;
	min-width: 0;
}

.automation-command-menu__groups {
	background: var(--surface-b);
	display: grid;
}

.automation-command-menu__group + .automation-command-menu__group {
	border-top: 1px solid var(--surface-d);
}

.automation-command-menu__group-header {
	background: var(--surface-a);
	font-size: 0.86rem;
	font-weight: 600;
	padding-left: 0.75rem;
}

.automation-command-menu__items {
	display: grid;
	padding: 0.2rem;
}

.automation-command-menu__items button {
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

.automation-command-menu__items button:hover {
	background: color-mix(in srgb, #8b35e6 24%, var(--surface-a));
	border-color: #8b35e6;
}

.automation-command-menu__items span {
	display: grid;
	min-width: 0;
}

.automation-command-menu__items strong,
.automation-command-menu__items small {
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.automation-command-menu__items small {
	color: var(--text-color-secondary);
	font-size: 0.72rem;
}

.automation-command-menu__items em {
	background: #7d32d4;
	border-radius: 3px;
	color: white;
	font-size: 0.66rem;
	font-style: normal;
	font-weight: 700;
	padding: 0.12rem 0.28rem;
}

.automation-command-menu__items em.trigger {
	background: #c24cff;
	color: #19001f;
}
</style>
