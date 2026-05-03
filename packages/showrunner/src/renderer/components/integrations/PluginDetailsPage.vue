<template>
	<div class="plugin-details">
		<header v-if="plugin" class="plugin-details__header">
			<div class="plugin-details__identity">
				<i :class="pluginIconClass" :style="{ color: plugin.color }" />
				<div>
					<p>Integration Plugin</p>
					<h2>{{ plugin.name }}</h2>
					<small>{{ plugin.id }} · {{ plugin.version || "unknown version" }}</small>
				</div>
			</div>
			<button type="button" class="plugin-details__toggle" :class="{ enabled, disabled: !enabled }" @click="togglePlugin">
				<i :class="enabled ? 'mdi mdi-power' : 'mdi mdi-power-off'" />
				<span>{{ enabled ? "On" : "Off" }}</span>
			</button>
		</header>

		<div v-if="!plugin" class="plugin-details__missing">
			<i class="mdi mdi-alert-circle-outline" />
			Plugin not found.
		</div>

		<template v-else>
			<label class="plugin-details__search">
				<i class="mdi mdi-magnify" />
				<input v-model="filterQuery" type="search" placeholder="Search integration details" />
			</label>

			<nav class="plugin-details__tabs" aria-label="Plugin detail sections">
				<button
					v-for="tab in detailTabs"
					:key="tab.id"
					type="button"
					:class="{ active: activeTab === tab.id }"
					@click="activeTab = tab.id"
				>
					<i :class="tab.icon" />
					<span>{{ tab.label }}</span>
					<em v-if="tab.count != null">{{ tab.count }}</em>
				</button>
			</nav>

			<template v-if="activeTab === 'overview'">
				<section class="plugin-details__section">
					<h3>Overview</h3>
					<p v-if="plugin.description">{{ plugin.description }}</p>
					<p v-else class="plugin-details__empty">No plugin description registered.</p>
				</section>

				<section class="plugin-details__stats">
					<div><strong>{{ Object.keys(plugin.actions).length }}</strong><span>actions</span></div>
					<div><strong>{{ Object.keys(plugin.triggers).length }}</strong><span>triggers</span></div>
					<div><strong>{{ Object.keys(plugin.settings).length }}</strong><span>settings</span></div>
					<div><strong>{{ Object.keys(plugin.state).length }}</strong><span>state values</span></div>
					<div><strong>{{ usage.length }}</strong><span>graph uses</span></div>
				</section>
			</template>

			<section v-else-if="activeTab === 'usage'" class="plugin-details__section">
				<h3>Used In Automations</h3>
				<div v-if="filteredUsage.length" class="plugin-details__usage-list">
					<article v-for="item in filteredUsage" :key="item.key" class="plugin-details__usage">
						<div>
							<strong>{{ item.automationName }}</strong>
							<small>{{ item.kind }} · {{ item.name }}</small>
						</div>
						<pre v-if="item.config">{{ item.config }}</pre>
					</article>
				</div>
				<p v-else class="plugin-details__empty">{{ emptyText("No current automations use this plugin.") }}</p>
			</section>

			<section v-else-if="activeTab === 'settings'" class="plugin-details__section">
				<h3>Settings</h3>
				<div v-if="filteredSettingRows.length" class="plugin-details__rows">
					<article v-for="row in filteredSettingRows" :key="row.id" class="plugin-details__row">
						<div>
							<strong>{{ row.name }}</strong>
							<small>{{ row.id }} · {{ row.type }}</small>
						</div>
						<code>{{ row.value }}</code>
					</article>
				</div>
				<p v-else class="plugin-details__empty">{{ emptyText("No plugin settings registered.") }}</p>
			</section>

			<section v-else-if="activeTab === 'actions'" class="plugin-details__section">
				<h3>Actions</h3>
				<div v-if="filteredActionRows.length" class="plugin-details__rows">
					<article v-for="row in filteredActionRows" :key="row.id" class="plugin-details__row">
						<div>
							<strong>{{ row.name }}</strong>
							<small>{{ row.id }} · {{ row.type }}</small>
						</div>
						<div class="plugin-details__chips">
							<span v-for="chip in row.config" :key="`config-${row.id}-${chip}`">{{ chip }}</span>
							<span v-for="chip in row.result" :key="`result-${row.id}-${chip}`" class="result">{{ chip }}</span>
						</div>
					</article>
				</div>
				<p v-else class="plugin-details__empty">{{ emptyText("No actions registered.") }}</p>
			</section>

			<section v-else-if="activeTab === 'triggers'" class="plugin-details__section">
				<h3>Triggers</h3>
				<div v-if="filteredTriggerRows.length" class="plugin-details__rows">
					<article v-for="row in filteredTriggerRows" :key="row.id" class="plugin-details__row">
						<div>
							<strong>{{ row.name }}</strong>
							<small>{{ row.id }}</small>
						</div>
						<div class="plugin-details__chips">
							<span v-for="chip in row.config" :key="`trigger-config-${row.id}-${chip}`">{{ chip }}</span>
							<span v-for="chip in row.context" :key="`trigger-context-${row.id}-${chip}`" class="result">{{ chip }}</span>
						</div>
					</article>
				</div>
				<p v-else class="plugin-details__empty">{{ emptyText("No triggers registered.") }}</p>
			</section>

			<section v-else-if="activeTab === 'state'" class="plugin-details__section">
				<h3>State</h3>
				<div v-if="filteredStateRows.length" class="plugin-details__rows">
					<article v-for="row in filteredStateRows" :key="row.id" class="plugin-details__row">
						<div>
							<strong>{{ row.name }}</strong>
							<small>{{ row.id }}</small>
						</div>
						<code>{{ row.value }}</code>
					</article>
				</div>
				<p v-else class="plugin-details__empty">{{ emptyText("No runtime state registered.") }}</p>
			</section>
		</template>
	</div>
</template>

<script setup lang="ts">
import { computed, ref } from "vue"
import { usePluginStore, useResourceStore } from "showrunner-ui-core"
import { pluginIcon } from "../../util/plugin-icons"

const props = defineProps<{
	pageData?: {
		pluginId?: string
	}
}>()

const pluginStore = usePluginStore()
const resourceStore = useResourceStore()
const pluginId = computed(() => props.pageData?.pluginId ?? "")
const plugin = computed(() => pluginStore.pluginMap.get(pluginId.value))
const enabled = computed(() => pluginStore.isPluginEnabled(pluginId.value))
const pluginIconClass = computed(() => pluginIcon(pluginId.value, plugin.value?.icon))
type DetailTab = "overview" | "usage" | "settings" | "actions" | "triggers" | "state"
const activeTab = ref<DetailTab>("overview")
const filterQuery = ref("")
const normalizedFilterQuery = computed(() => filterQuery.value.trim().toLocaleLowerCase())

const detailTabs = computed<Array<{ id: DetailTab; label: string; icon: string; count?: number }>>(() => [
	{ id: "overview", label: "Overview", icon: "mdi mdi-information-outline" },
	{ id: "usage", label: "Usage", icon: "mdi mdi-graph-outline", count: filteredUsage.value.length },
	{ id: "settings", label: "Settings", icon: "mdi mdi-cog-outline", count: filteredSettingRows.value.length },
	{ id: "actions", label: "Actions", icon: "mdi mdi-lightning-bolt-outline", count: filteredActionRows.value.length },
	{ id: "triggers", label: "Triggers", icon: "mdi mdi-bell-ring-outline", count: filteredTriggerRows.value.length },
	{ id: "state", label: "State", icon: "mdi mdi-database-outline", count: filteredStateRows.value.length },
])

const settingRows = computed(() => {
	if (!plugin.value) return []
	return Object.entries(plugin.value.settings)
		.map(([id, setting]: [string, any]) => ({
			id,
			name: setting.schema?.name || setting.name || id,
			type: setting.type,
			value: setting.type === "secret"
				? maskSecret(setting.value)
				: setting.type === "value"
					? formatValue(setting.value)
					: setting.type === "resource"
						? `Resource type: ${setting.resourceId}`
						: "Custom settings component",
		}))
		.sort((a, b) => a.name.localeCompare(b.name))
})

const stateRows = computed(() => {
	if (!plugin.value) return []
	return Object.entries(plugin.value.state)
		.map(([id, state]: [string, any]) => ({
			id,
			name: state.schema?.name || id,
			value: formatValue(state.value),
		}))
		.sort((a, b) => a.name.localeCompare(b.name))
})

const actionRows = computed(() => {
	if (!plugin.value) return []
	return Object.entries(plugin.value.actions)
		.map(([id, action]: [string, any]) => ({
			id,
			name: action.name || id,
			type: action.type,
			config: schemaPorts(action.config),
			result: action.type === "regular" ? schemaPorts(action.result) : [],
		}))
		.sort((a, b) => a.name.localeCompare(b.name))
})

const triggerRows = computed(() => {
	if (!plugin.value) return []
	return Object.entries(plugin.value.triggers)
		.map(([id, trigger]: [string, any]) => ({
			id,
			name: trigger.name || id,
			config: schemaPorts(trigger.config),
			context: typeof trigger.context === "function" ? ["dynamic context"] : schemaPorts(trigger.context),
		}))
		.sort((a, b) => a.name.localeCompare(b.name))
})

const usage = computed(() => {
	const storage = resourceStore.resourceMap.get("Automation")
	if (!storage || !plugin.value) return []
	const items: Array<{ key: string; automationName: string; kind: string; name: string; config: string }> = []
	for (const resource of storage.resources.values()) {
		const config = resource.config as any
		const automationName = config.name || resource.id
		if (config.plugin === pluginId.value) {
			items.push({
				key: `${resource.id}:trigger`,
				automationName,
				kind: "Trigger",
				name: config.trigger || "(missing trigger)",
				config: formatValue(config.config ?? {}),
			})
		}
		for (const node of config.graph?.nodes ?? []) {
			if (node?.type !== "action" || node.plugin !== pluginId.value) continue
			items.push({
				key: `${resource.id}:${node.id}`,
				automationName,
				kind: "Action node",
				name: node.action || node.id,
				config: formatValue(node.config ?? {}),
			})
		}
		for (const subgraph of config.subgraphs ?? []) {
			for (const node of subgraph.nodes ?? []) {
				if (node?.type !== "action" || node.plugin !== pluginId.value) continue
				items.push({
					key: `${resource.id}:${subgraph.id}:${node.id}`,
					automationName,
					kind: `Subgraph action · ${subgraph.name || subgraph.id}`,
					name: node.action || node.id,
					config: formatValue(node.config ?? {}),
				})
			}
		}
	}
	return items.sort((a, b) => a.automationName.localeCompare(b.automationName) || a.name.localeCompare(b.name))
})

const filteredSettingRows = computed(() => filterRows(settingRows.value))
const filteredStateRows = computed(() => filterRows(stateRows.value))
const filteredActionRows = computed(() => filterRows(actionRows.value))
const filteredTriggerRows = computed(() => filterRows(triggerRows.value))
const filteredUsage = computed(() => filterRows(usage.value))

function filterRows<T>(rows: T[]): T[] {
	const query = normalizedFilterQuery.value
	if (!query) return rows
	return rows.filter((row) => JSON.stringify(row).toLocaleLowerCase().includes(query))
}

function emptyText(fallback: string) {
	return normalizedFilterQuery.value ? `No matches for "${filterQuery.value.trim()}".` : fallback
}

function togglePlugin() {
	if (!plugin.value) return
	pluginStore.togglePluginEnabled(plugin.value.id)
}

function schemaPorts(schema: any) {
	if (!schema || schema.type !== Object || !schema.properties) return []
	return Object.entries(schema.properties).map(([id, prop]: [string, any]) => {
		const name = prop?.name || id
		const type = typeName(prop?.type)
		return `${name}: ${type}`
	})
}

function typeName(type: unknown) {
	if (typeof type === "function") return type.name || "custom"
	if (type && typeof type === "object" && "name" in type) return String((type as any).name)
	return String(type || "unknown")
}

function formatValue(value: unknown) {
	if (value === undefined) return "undefined"
	try {
		return JSON.stringify(value, null, "\t")
	} catch {
		return String(value)
	}
}

function maskSecret(value: unknown) {
	if (value == null || value === "") return "(empty)"
	return "••••••••"
}
</script>

<style scoped>
.plugin-details {
	align-content: start;
	display: grid;
	gap: 1rem;
	height: 100%;
	grid-auto-rows: max-content;
	overflow: auto;
	padding: 1rem;
}

.plugin-details__header,
.plugin-details__section,
.plugin-details__stats,
.plugin-details__search,
.plugin-details__tabs {
	background: var(--surface-b);
	border: 1px solid var(--surface-d);
	border-radius: 6px;
}

.plugin-details__header {
	align-items: center;
	display: flex;
	justify-content: space-between;
	padding: 1rem;
}

.plugin-details__identity {
	align-items: center;
	display: flex;
	gap: 0.85rem;
	min-width: 0;
}

.plugin-details__identity > i {
	font-size: 2rem;
}

.plugin-details__identity p,
.plugin-details__identity h2 {
	margin: 0;
}

.plugin-details__identity p {
	color: var(--text-color-secondary);
	font-size: 0.72rem;
	font-weight: 700;
	text-transform: uppercase;
}

.plugin-details__identity small,
.plugin-details__row small,
.plugin-details__usage small,
.plugin-details__empty {
	color: var(--text-color-secondary);
}

.plugin-details__toggle {
	align-items: center;
	border: 1px solid transparent;
	border-radius: 4px;
	cursor: pointer;
	display: flex;
	gap: 0.4rem;
	padding: 0.45rem 0.7rem;
}

.plugin-details__toggle.enabled {
	background: rgb(21 128 61 / 0.28);
	border-color: rgb(34 197 94 / 0.5);
	color: #bbf7d0;
}

.plugin-details__toggle.disabled {
	background: rgb(153 27 27 / 0.28);
	border-color: rgb(248 113 113 / 0.5);
	color: #fecaca;
}

.plugin-details__stats {
	display: grid;
	gap: 0.5rem;
	grid-template-columns: repeat(auto-fit, minmax(8rem, 1fr));
	padding: 0.75rem;
}

.plugin-details__search {
	align-items: center;
	display: flex;
	gap: 0.5rem;
	padding: 0.55rem 0.7rem;
}

.plugin-details__search input {
	background: transparent;
	border: 0;
	color: var(--text-color);
	font: inherit;
	min-width: 0;
	outline: none;
	width: 100%;
}

.plugin-details__tabs {
	display: flex;
	flex-wrap: wrap;
	gap: 0.35rem;
	padding: 0.45rem;
}

.plugin-details__tabs button {
	align-items: center;
	background: transparent;
	border: 1px solid transparent;
	border-radius: 4px;
	color: var(--text-color-secondary);
	cursor: pointer;
	display: flex;
	gap: 0.35rem;
	min-height: 2rem;
	padding: 0.35rem 0.6rem;
}

.plugin-details__tabs button:hover {
	background: var(--surface-a);
	color: var(--text-color);
}

.plugin-details__tabs button.active {
	background: rgb(255 255 255 / 0.08);
	border-color: rgb(255 255 255 / 0.16);
	color: var(--text-color);
}

.plugin-details__tabs em {
	background: rgb(255 255 255 / 0.12);
	border-radius: 999px;
	font-size: 0.72rem;
	font-style: normal;
	line-height: 1;
	min-width: 1.25rem;
	padding: 0.2rem 0.35rem;
	text-align: center;
}

.plugin-details__stats div {
	background: var(--surface-a);
	border: 1px solid var(--surface-d);
	border-radius: 4px;
	display: grid;
	gap: 0.1rem;
	padding: 0.65rem;
}

.plugin-details__stats strong {
	font-size: 1.35rem;
}

.plugin-details__stats span {
	color: var(--text-color-secondary);
	font-size: 0.78rem;
}

.plugin-details__section {
	align-content: start;
	display: grid;
	gap: 0.75rem;
	padding: 1rem;
}

.plugin-details__section h3 {
	margin: 0;
}

.plugin-details__rows,
.plugin-details__usage-list {
	display: grid;
	gap: 0.35rem;
}

.plugin-details__row,
.plugin-details__usage {
	background: var(--surface-a);
	border: 1px solid var(--surface-d);
	border-radius: 4px;
	display: grid;
	gap: 0.45rem;
	grid-template-columns: minmax(12rem, 0.45fr) minmax(0, 1fr);
	padding: 0.5rem 0.6rem;
}

.plugin-details__row > div:first-child,
.plugin-details__usage > div:first-child {
	display: grid;
	gap: 0.15rem;
}

.plugin-details__chips {
	display: flex;
	flex-wrap: wrap;
	gap: 0.25rem;
}

.plugin-details__chips span {
	background: rgb(255 255 255 / 0.08);
	border: 1px solid rgb(255 255 255 / 0.14);
	border-radius: 3px;
	font-size: 0.7rem;
	line-height: 1.2;
	padding: 0.16rem 0.3rem;
}

.plugin-details__chips span.result {
	border-color: rgb(129 199 132 / 0.45);
	color: #b9f6ca;
}

.plugin-details code,
.plugin-details pre {
	background: rgb(0 0 0 / 0.24);
	border: 1px solid rgb(255 255 255 / 0.1);
	border-radius: 4px;
	color: #e6e6e6;
	font-family: ui-monospace, SFMono-Regular, Consolas, "Liberation Mono", monospace;
	font-size: 0.75rem;
	margin: 0;
	overflow: auto;
	padding: 0.45rem;
	white-space: pre-wrap;
}

.plugin-details__missing {
	align-items: center;
	color: var(--text-color-secondary);
	display: flex;
	gap: 0.5rem;
}

@media (max-width: 900px) {
	.plugin-details__row,
	.plugin-details__usage {
		grid-template-columns: 1fr;
	}
}
</style>
