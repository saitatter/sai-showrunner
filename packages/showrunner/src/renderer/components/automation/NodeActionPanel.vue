<template>
	<div class="node-action-panel">
		<div class="node-action-panel__picker">
			<label>
				<span>Add Action</span>
				<input :value="actionPaletteQuery" type="search" placeholder="Search plugin or action..." @input="$emit('update:actionPaletteQuery', ($event.target as HTMLInputElement).value)" />
				<select :value="selectedActionToAdd" @change="$emit('update:selectedActionToAdd', ($event.target as HTMLSelectElement).value)">
					<option value="">Choose an action...</option>
					<optgroup v-for="plugin in actionPalette" :key="plugin.id" :label="plugin.name">
						<option v-for="action in plugin.actions" :key="action.key" :value="action.key">
							{{ action.name }}
						</option>
					</optgroup>
				</select>
			</label>
			<button type="button" :disabled="!selectedActionToAdd" @click="onAddActionFromPalette()">
				<i class="mdi mdi-plus" />
				Insert After Selection
			</button>
			<div class="node-action-panel__palette-list">
				<button
					v-for="action in flatActionPalette"
					:key="action.key"
					type="button"
					draggable="true"
					@click="$emit('update:selectedActionToAdd', action.key)"
					@dragstart="onStartActionPaletteDrag($event, action.key)"
				>
					<i class="mdi mdi-drag" />
					<span>{{ action.pluginName }}</span>
					<strong>{{ action.name }}</strong>
				</button>
			</div>
		</div>
		<div class="node-action-panel__grid">
			<button type="button" :disabled="!canEditSelectedAction" @click="onDuplicateSelectedAction()">
				<i class="mdi mdi-content-duplicate" />
				Duplicate
			</button>
			<button type="button" :disabled="!canMoveSelectedAction(-1)" @click="onMoveSelectedAction(-1)">
				<i class="mdi mdi-arrow-left" />
				Move Left
			</button>
			<button type="button" :disabled="!canMoveSelectedAction(1)" @click="onMoveSelectedAction(1)">
				<i class="mdi mdi-arrow-right" />
				Move Right
			</button>
			<button type="button" class="danger" :disabled="!canEditSelectedAction" @click="onDeleteSelectedAction()">
				<i class="mdi mdi-trash-can-outline" />
				Delete
			</button>
		</div>
		<button type="button" @click="onResetSelectedNodePosition()">
			<i class="mdi mdi-crosshairs-gps" />
			Reset Visual Position
		</button>
		<button type="button" :disabled="selectedNodeCount < 1" @click="onCollapseSelectionToSubgraph()">
			<i class="mdi mdi-function" />
			Collapse Selection to Subgraph
		</button>
	</div>
</template>

<script setup lang="ts">
interface ActionPalettePlugin {
	id: string
	name: string
	actions: {
		key: string
		name: string
		searchText?: string
	}[]
}

interface FlatActionPaletteItem {
	key: string
	name: string
	pluginName: string
	searchText?: string
}

defineProps<{
	actionPaletteQuery: string
	selectedActionToAdd: string
	actionPalette: ActionPalettePlugin[]
	flatActionPalette: FlatActionPaletteItem[]
	canEditSelectedAction: boolean
	selectedNodeCount: number
	onAddActionFromPalette: () => void
	onStartActionPaletteDrag: (event: DragEvent, actionKey: string) => void
	onDuplicateSelectedAction: () => void
	onMoveSelectedAction: (direction: -1 | 1) => void
	onDeleteSelectedAction: () => void
	onResetSelectedNodePosition: () => void
	onCollapseSelectionToSubgraph: () => void
	canMoveSelectedAction: (direction: -1 | 1) => boolean
}>()

defineEmits<{
	"update:actionPaletteQuery": [value: string]
	"update:selectedActionToAdd": [value: string]
}>()
</script>

<style scoped>
.node-action-panel {
	display: grid;
	gap: 0.5rem;
	padding: 0.65rem;
}

.node-action-panel__picker {
	display: grid;
	gap: 0.5rem;
}

.node-action-panel__picker label {
	display: grid;
	gap: 0.3rem;
}

.node-action-panel__picker span {
	color: #d9d9d9;
	font-size: 0.78rem;
}

.node-action-panel__picker input,
.node-action-panel__picker select {
	background: #0e0e0e;
	border: 1px solid #4d4d4d;
	border-radius: 4px;
	color: var(--text-color);
	min-width: 0;
	padding: 0.55rem;
}

.node-action-panel__grid {
	display: grid;
	gap: 0.5rem;
	grid-template-columns: 1fr 1fr;
}

.node-action-panel__palette-list {
	display: grid;
	gap: 0.35rem;
	max-height: 13rem;
	overflow: auto;
	padding-right: 0.15rem;
}

.node-action-panel__palette-list button {
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

.node-action-panel__palette-list button:active {
	cursor: grabbing;
}

.node-action-panel__palette-list span,
.node-action-panel__palette-list strong {
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.node-action-panel__palette-list span {
	color: #bbb;
}

.node-action-panel button {
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

.node-action-panel button.danger {
	background: #3a171b;
	border-color: #8f3744;
}

.node-action-panel button:disabled {
	cursor: not-allowed;
	opacity: 0.45;
}
</style>
