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
			<section v-if="plugin.description" class="plugin-details__section">
				<p>{{ plugin.description }}</p>
			</section>

			<section class="plugin-details__stats">
				<div><strong>{{ Object.keys(plugin.actions).length }}</strong><span>actions</span></div>
				<div><strong>{{ Object.keys(plugin.triggers).length }}</strong><span>triggers</span></div>
				<div><strong>{{ Object.keys(plugin.settings).length }}</strong><span>settings</span></div>
				<div><strong>{{ Object.keys(plugin.state).length }}</strong><span>state values</span></div>
				<div><strong>{{ usage.length }}</strong><span>graph uses</span></div>
			</section>

			<section class="plugin-details__section">
				<h3>Used In Automations</h3>
				<div v-if="usage.length" class="plugin-details__usage-list">
					<article v-for="item in usage" :key="item.key" class="plugin-details__usage">
						<div>
							<strong>{{ item.automationName }}</strong>
							<small>{{ item.kind }} · {{ item.name }}</small>
						</div>
						<pre v-if="item.config">{{ item.config }}</pre>
					</article>
				</div>
				<p v-else class="plugin-details__empty">No current automations use this plugin.</p>
			</section>

			<section class="plugin-details__section">
				<h3>Settings</h3>
				<div v-if="settingRows.length" class="plugin-details__rows">
					<article v-for="row in settingRows" :key="row.id" class="plugin-details__row">
						<div>
							<strong>{{ row.name }}</strong>
							<small>{{ row.id }} · {{ row.type }}</small>
						</div>
						<code>{{ row.value }}</code>
					</article>
				</div>
				<p v-else class="plugin-details__empty">No plugin settings registered.</p>
			</section>

			<section class="plugin-details__section">
				<h3>Actions</h3>
				<div v-if="actionRows.length" class="plugin-details__rows">
					<article v-for="row in actionRows" :key="row.id" class="plugin-details__row">
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
				<p v-else class="plugin-details__empty">No actions registered.</p>
			</section>

			<section class="plugin-details__section">
				<h3>Triggers</h3>
				<div v-if="triggerRows.length" class="plugin-details__rows">
					<article v-for="row in triggerRows" :key="row.id" class="plugin-details__row">
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
				<p v-else class="plugin-details__empty">No triggers registered.</p>
			</section>

			<section class="plugin-details__section">
				<h3>State</h3>
				<div v-if="stateRows.length" class="plugin-details__rows">
					<article v-for="row in stateRows" :key="row.id" class="plugin-details__row">
						<div>
							<strong>{{ row.name }}</strong>
							<small>{{ row.id }}</small>
						</div>
						<code>{{ row.value }}</code>
					</article>
				</div>
				<p v-else class="plugin-details__empty">No runtime state registered.</p>
			</section>
		</template>
	</div>
</template>

<script setup lang="ts">
import { computed } from "vue"
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
	display: grid;
	gap: 1rem;
	height: 100%;
	overflow: auto;
	padding: 1rem;
}

.plugin-details__header,
.plugin-details__section,
.plugin-details__stats {
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
	gap: 0.5rem;
}

.plugin-details__row,
.plugin-details__usage {
	background: var(--surface-a);
	border: 1px solid var(--surface-d);
	border-radius: 4px;
	display: grid;
	gap: 0.5rem;
	padding: 0.65rem;
}

.plugin-details__chips {
	display: flex;
	flex-wrap: wrap;
	gap: 0.35rem;
}

.plugin-details__chips span {
	background: rgb(255 255 255 / 0.08);
	border: 1px solid rgb(255 255 255 / 0.14);
	border-radius: 3px;
	font-size: 0.75rem;
	padding: 0.2rem 0.4rem;
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
</style>
