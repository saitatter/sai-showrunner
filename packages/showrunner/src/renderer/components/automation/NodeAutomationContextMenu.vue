<template>
	<collapsible-context-menu
		:x="contextMenu.x"
		:y="contextMenu.y"
		:title="contextMenu.nodeId ? 'Node Menu' : 'Canvas Menu'"
		:subtitle="contextMenuSubtitle"
		@close="onCloseContextMenu()"
	>
		<template #search>
			<label class="node-automation__context-menu-search">
				<i class="mdi mdi-magnify" />
				<input v-model="contextMenuQueryModel" type="search" placeholder="Search triggers or actions..." />
			</label>
		</template>
		<section v-if="recentContextItems.length && !contextMenuQuery" class="node-automation__menu-section">
			<div class="node-automation__menu-section-header node-automation__menu-section-header--static">
				<span><i class="mdi mdi-history" /> Recently Used</span>
			</div>
			<div class="node-automation__menu-items">
				<button v-for="item in recentContextItems" :key="`recent-${item.key}`" type="button" @click="item.kind === 'trigger' ? onSelectTriggerFromContext(item.key) : onSelectActionFromContext(item.key)">
					<i :class="item.icon" :style="{ color: item.color }" />
					<span>
						<strong>{{ item.name }}</strong>
					</span>
					<em :class="item.kind === 'trigger' ? 'trigger' : ''">{{ item.kind === 'trigger' ? 'Trigger' : 'Action' }}</em>
				</button>
			</div>
		</section>
		<section v-if="contextMenuSearchResults.length" class="node-automation__menu-section">
			<div class="node-automation__menu-section-header node-automation__menu-section-header--static">
				<span><i class="mdi mdi-filter-variant" /> Matching Nodes</span>
			</div>
			<div class="node-automation__menu-items">
				<button v-for="item in contextMenuSearchResults" :key="`search-${item.kind}-${item.key}`" type="button" @click="onSelectContextSearchResult(item)">
					<i :class="item.icon" :style="{ color: item.color }" />
					<span>
						<strong>{{ item.name }}</strong>
						<small>{{ item.detail }}</small>
					</span>
					<em :class="item.kind === 'trigger' ? 'trigger' : ''">{{ item.label }}</em>
				</button>
			</div>
		</section>
		<section v-else-if="hiddenPluginSearchHint" class="node-automation__menu-section node-automation__menu-hint">
			<i class="mdi mdi-eye-off-outline" />
			<span>{{ hiddenPluginSearchHint }}</span>
		</section>
		<section v-if="actionCategoryGroups.length" class="node-automation__menu-section">
			<button type="button" class="node-automation__menu-section-header" data-context-section="categories" :aria-expanded="isContextGroupOpen('categories')" @click="toggleContextGroup('categories')">
				<span><i class="mdi mdi-shape-outline" /> Categories</span>
				<i :class="isContextGroupOpen('categories') ? 'mdi mdi-chevron-up' : 'mdi mdi-chevron-down'" />
			</button>
			<div v-if="isContextGroupOpen('categories')" class="node-automation__menu-groups">
				<div v-for="group in actionCategoryGroups" :key="group.id" class="node-automation__menu-group">
					<button type="button" class="node-automation__menu-group-header" :aria-expanded="isContextGroupOpen(`category:${group.id}`)" @click="toggleContextGroup(`category:${group.id}`)">
						<span>
							<i :class="group.icon" :style="{ color: group.color }" />
							{{ group.name }}
						</span>
						<i :class="isContextGroupOpen(`category:${group.id}`) ? 'mdi mdi-chevron-up' : 'mdi mdi-chevron-down'" />
					</button>
					<div v-if="isContextGroupOpen(`category:${group.id}`)" class="node-automation__menu-items">
						<button v-for="item in group.items" :key="`category-${group.id}-${item.key}`" type="button" @click="onSelectActionFromContext(item.key)">
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
		<section class="node-automation__menu-section">
			<button type="button" class="node-automation__menu-section-header" data-context-section="integrations" :aria-expanded="isContextGroupOpen('integrations')" @click="toggleContextGroup('integrations')">
				<span><i class="mdi mdi-puzzle-outline" /> Integrations</span>
				<i :class="isContextGroupOpen('integrations') ? 'mdi mdi-chevron-up' : 'mdi mdi-chevron-down'" />
			</button>
			<div v-if="isContextGroupOpen('integrations')">
				<section v-if="!pendingFlowConnection" class="node-automation__menu-section node-automation__menu-subsection">
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
								<button v-for="item in group.items" :key="item.key" type="button" @click="onSelectTriggerFromContext(item.key)">
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
				<section class="node-automation__menu-section node-automation__menu-subsection">
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
								<button v-for="item in group.items" :key="item.key" type="button" @click="onSelectActionFromContext(item.key)">
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
		<section v-if="conversionContextItems.length || !pendingFlowConnection" class="node-automation__menu-section">
			<button type="button" class="node-automation__menu-section-header" data-context-section="data" :aria-expanded="isContextGroupOpen('data')" @click="toggleContextGroup('data')">
				<span><i class="mdi mdi-database-outline" /> Data</span>
				<i :class="isContextGroupOpen('data') ? 'mdi mdi-chevron-up' : 'mdi mdi-chevron-down'" />
			</button>
			<div v-if="isContextGroupOpen('data')">
				<div v-if="conversionContextItems.length" class="node-automation__menu-subtitle">
					<i class="mdi mdi-swap-horizontal" />
					<span>Conversions</span>
				</div>
				<div v-if="conversionContextItems.length" class="node-automation__menu-items">
					<button v-for="item in conversionContextItems" :key="`conversion-${item.key}`" type="button" @click="onSelectActionFromContext(item.key)">
						<i :class="item.icon" :style="{ color: item.color }" />
						<span>
							<strong>{{ item.name }}</strong>
							<small>{{ item.pluginName }}</small>
						</span>
						<em>Convert</em>
					</button>
				</div>
				<div v-if="!pendingFlowConnection" class="node-automation__menu-subtitle">
					<i class="mdi mdi-variable" />
					<span>Variables</span>
				</div>
				<div v-if="!pendingFlowConnection" class="node-automation__menu-items">
					<button type="button" @click="onAddVariableNode('string')">
						<i class="mdi mdi-format-text" style="color: #81c784" />
						<span><strong>String Variable</strong></span>
						<em>Variable</em>
					</button>
					<button type="button" @click="onAddVariableNode('number')">
						<i class="mdi mdi-numeric" style="color: #4fc3f7" />
						<span><strong>Number Variable</strong></span>
						<em>Variable</em>
					</button>
					<button type="button" @click="onAddVariableNode('boolean')">
						<i class="mdi mdi-toggle-switch-outline" style="color: #ffb74d" />
						<span><strong>Boolean Variable</strong></span>
						<em>Variable</em>
					</button>
					<button type="button" @click="onAddVariableNode('color')">
						<i class="mdi mdi-palette" style="color: #f06292" />
						<span><strong>Color Variable</strong></span>
						<em>Variable</em>
					</button>
				</div>
			</div>
		</section>
		<section class="node-automation__menu-section">
			<button type="button" class="node-automation__menu-section-header" data-context-section="flow" :aria-expanded="isContextGroupOpen('flow')" @click="toggleContextGroup('flow')">
				<span><i class="mdi mdi-vector-polyline" /> Flow</span>
				<i :class="isContextGroupOpen('flow') ? 'mdi mdi-chevron-up' : 'mdi mdi-chevron-down'" />
			</button>
			<div v-if="isContextGroupOpen('flow')">
				<div class="node-automation__menu-items">
					<button type="button" @click="onAddControlFlowNode('if')">
						<i class="mdi mdi-source-branch" style="color: #64b5f6" />
						<span><strong>If / Else</strong><small>Conditional branch</small></span>
						<em>Control</em>
					</button>
					<button type="button" @click="onAddControlFlowNode('switch')">
						<i class="mdi mdi-source-fork" style="color: #64b5f6" />
						<span><strong>Switch</strong><small>Multi-way branch</small></span>
						<em>Control</em>
					</button>
					<button type="button" @click="onAddControlFlowNode('for')">
						<i class="mdi mdi-repeat" style="color: #68d391" />
						<span><strong>For Loop</strong><small>Counter-based loop</small></span>
						<em>Control</em>
					</button>
					<button type="button" @click="onAddControlFlowNode('forEach')">
						<i class="mdi mdi-format-list-numbered" style="color: #68d391" />
						<span><strong>For Each</strong><small>Iterate over collection</small></span>
						<em>Control</em>
					</button>
					<button type="button" @click="onAddControlFlowNode('while')">
						<i class="mdi mdi-sync" style="color: #68d391" />
						<span><strong>While Loop</strong><small>Condition-based loop</small></span>
						<em>Control</em>
					</button>
					<button type="button" @click="onAddControlFlowNode('break')">
						<i class="mdi mdi-debug-step-out" style="color: #ef9a9a" />
						<span><strong>Break</strong><small>Exit current loop</small></span>
						<em>Control</em>
					</button>
					<button type="button" @click="onAddControlFlowNode('continue')">
						<i class="mdi mdi-skip-next" style="color: #ef9a9a" />
						<span><strong>Continue</strong><small>Next iteration</small></span>
						<em>Control</em>
					</button>
					<button type="button" @click="onAddControlFlowNode('return')">
						<i class="mdi mdi-keyboard-return" style="color: #ef9a9a" />
						<span><strong>Return</strong><small>End execution</small></span>
						<em>Control</em>
					</button>
					<hr class="node-automation__menu-divider" />
					<template v-if="subgraphsList.length">
						<button v-for="sg in subgraphsList" :key="`sg-${sg.id}`" type="button" @click="onAddSubgraphCallNode(sg.id)">
							<i class="mdi mdi-function" style="color: #ce93d8" />
							<span><strong>{{ sg.name || 'Unnamed' }}</strong><small>Call subgraph</small></span>
							<em>Subgraph</em>
						</button>
						<hr class="node-automation__menu-divider" />
					</template>
				</div>
			</div>
		</section>
	</collapsible-context-menu>
</template>

<script setup lang="ts">
import { computed } from "vue"
import { CollapsibleContextMenu } from "showrunner-ui-core"
import type { GraphNodeType, SubgraphDefinition } from "showrunner-schema"
import type { ContextSearchResult } from "./useNodeContextMenuSearch"

type VariableNodeType = "string" | "number" | "boolean" | "color"
type ControlFlowNodeType = Exclude<GraphNodeType, "action" | "subgraphCall">

interface ContextMenuState {
	x: number
	y: number
	nodeId?: string
}

interface MenuItem {
	key: string
	name: string
	pluginName: string
	icon: string
	color: string
}

interface MenuGroup {
	id: string
	name: string
	icon: string
	color: string
	items: MenuItem[]
}

interface RecentItem {
	key: string
	kind: "action" | "trigger"
	name: string
	icon: string
	color: string
}

const props = defineProps<{
	contextMenu: ContextMenuState
	contextMenuQuery: string
	contextMenuSubtitle?: string
	recentContextItems: RecentItem[]
	contextMenuSearchResults: ContextSearchResult[]
	hiddenPluginSearchHint: string
	actionCategoryGroups: MenuGroup[]
	actionContextGroups: MenuGroup[]
	conversionContextItems: MenuItem[]
	triggerContextGroups: MenuGroup[]
	pendingFlowConnection: boolean
	subgraphsList: SubgraphDefinition[]
	isContextGroupOpen: (id: string) => boolean
	toggleContextGroup: (id: string) => void
	onCloseContextMenu: () => void
	onSelectActionFromContext: (actionKey: string) => void
	onSelectTriggerFromContext: (triggerKey: string) => void
	onSelectContextSearchResult: (item: ContextSearchResult) => void
	onAddVariableNode: (type: VariableNodeType) => void
	onAddControlFlowNode: (type: ControlFlowNodeType) => void
	onAddSubgraphCallNode: (subgraphId: string) => void
}>()

const emit = defineEmits<{
	"update:contextMenuQuery": [value: string]
}>()

const contextMenuQueryModel = computed({
	get: () => props.contextMenuQuery,
	set: (value: string) => emit("update:contextMenuQuery", value),
})
</script>

<style scoped>
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

.node-automation__menu-subsection {
	border: 0;
	border-radius: 0;
}

.node-automation__menu-hint {
	align-items: center;
	color: var(--text-color-secondary);
	display: flex;
	gap: 0.5rem;
	padding: 0.7rem;
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

.node-automation__menu-section-header--static {
	cursor: default;
	font-size: 0.8rem;
	opacity: 0.7;
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

.node-automation__menu-subtitle {
	align-items: center;
	color: var(--text-color-secondary);
	display: flex;
	font-size: 0.72rem;
	font-weight: 700;
	gap: 0.35rem;
	letter-spacing: 0;
	padding: 0.45rem 0.5rem 0.1rem;
	text-transform: uppercase;
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

.node-automation__menu-items button:focus-visible {
	background: color-mix(in srgb, #8b35e6 28%, var(--surface-a));
	border-color: rgb(233 170 255 / 0.7);
	outline: 2px solid rgb(233 170 255 / 0.45);
	outline-offset: 1px;
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

.node-automation__menu-divider {
	border: none;
	border-top: 1px solid #333;
	margin: 6px 0;
}
</style>
