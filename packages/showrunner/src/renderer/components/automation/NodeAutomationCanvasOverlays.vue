<template>
	<div v-if="canvasSearchOpen" class="node-automation__canvas-search" @click.stop @pointerdown.stop>
		<i class="mdi mdi-magnify" />
		<input
			ref="searchInputRef"
			v-model="canvasSearchQueryModel"
			type="search"
			placeholder="Find node..."
			@keydown.enter.prevent="onCycleSearchResult(1)"
			@keydown.escape.prevent="onCloseCanvasSearch()"
			@keydown.up.prevent="onCycleSearchResult(-1)"
			@keydown.down.prevent="onCycleSearchResult(1)"
		/>
		<span v-if="canvasSearchResultCount" class="node-automation__search-count">
			{{ canvasSearchIndex + 1 }}/{{ canvasSearchResultCount }}
		</span>
		<span v-else-if="canvasSearchQuery" class="node-automation__search-count">0</span>
		<button type="button" aria-label="Previous" @click="onCycleSearchResult(-1)"><i class="mdi mdi-chevron-up" /></button>
		<button type="button" aria-label="Next" @click="onCycleSearchResult(1)"><i class="mdi mdi-chevron-down" /></button>
		<button type="button" aria-label="Close" @click="onCloseCanvasSearch()"><i class="mdi mdi-close" /></button>
	</div>

	<div v-if="activeSubgraph" class="node-automation__subgraph-breadcrumb">
		<button type="button" @click="onOpenMainCanvas()">
			<i class="mdi mdi-arrow-left" /> Main graph
		</button>
		<span>/</span>
		<strong>{{ activeSubgraph.name || "Unnamed Subgraph" }}</strong>
		<small>{{ activeSubgraph.nodes.length }} nodes, {{ activeSubgraph.dataWires?.length ?? 0 }} data wires</small>
	</div>

	<div v-if="invalidDataWireIssues.length" class="node-automation__wire-health" @click.stop @pointerdown.stop>
		<i class="mdi mdi-alert-circle-outline" />
		<div>
			<strong>{{ invalidDataWireIssues.length }} invalid data wire{{ invalidDataWireIssues.length === 1 ? "" : "s" }}</strong>
			<small>{{ invalidDataWireIssues[0].message }}</small>
		</div>
		<button type="button" @click="onSelectDataWireIssue(invalidDataWireIssues[0])">Select</button>
		<button type="button" @click="onCleanupInvalidDataWires()">Clean up</button>
	</div>

	<div v-if="invalidFlowEdgeIssues.length" class="node-automation__wire-health" @click.stop @pointerdown.stop>
		<i class="mdi mdi-alert-circle-outline" />
		<div>
			<strong>{{ invalidFlowEdgeIssues.length }} invalid sequence edge{{ invalidFlowEdgeIssues.length === 1 ? "" : "s" }}</strong>
			<small>{{ invalidFlowEdgeIssues[0].message }}</small>
		</div>
		<button type="button" @click="onSelectFlowEdgeIssue(invalidFlowEdgeIssues[0])">Select</button>
		<button type="button" @click="onCleanupInvalidFlowEdges()">Clean up</button>
	</div>
</template>

<script setup lang="ts">
import { computed, ref } from "vue"
import type { SubgraphDefinition } from "showrunner-schema"

interface InvalidDataWireIssue {
	id: string
	message: string
}

interface InvalidFlowEdgeIssue {
	id: string
	message: string
}

const props = defineProps<{
	canvasSearchOpen: boolean
	canvasSearchQuery: string
	canvasSearchIndex: number
	canvasSearchResultCount: number
	activeSubgraph?: SubgraphDefinition
	invalidDataWireIssues: InvalidDataWireIssue[]
	invalidFlowEdgeIssues: InvalidFlowEdgeIssue[]
	onCycleSearchResult: (direction: -1 | 1) => void
	onCloseCanvasSearch: () => void
	onOpenMainCanvas: () => void
	onSelectDataWireIssue: (issue: InvalidDataWireIssue) => void
	onCleanupInvalidDataWires: () => void
	onSelectFlowEdgeIssue: (issue: InvalidFlowEdgeIssue) => void
	onCleanupInvalidFlowEdges: () => void
}>()

const emit = defineEmits<{
	"update:canvasSearchQuery": [value: string]
}>()

const searchInputRef = ref<HTMLInputElement>()

const canvasSearchQueryModel = computed({
	get: () => props.canvasSearchQuery,
	set: (value: string) => emit("update:canvasSearchQuery", value),
})

function focusSearchInput() {
	searchInputRef.value?.focus()
}

defineExpose({
	focusSearchInput,
})
</script>

<style scoped>
.node-automation__canvas-search {
	align-items: center;
	background: rgb(0 0 0 / 0.72);
	border: 1px solid rgb(255 255 255 / 0.12);
	border-radius: 6px;
	display: flex;
	gap: 0.35rem;
	padding: 0.3rem 0.5rem;
	pointer-events: auto;
	position: absolute;
	right: 0.75rem;
	top: 3.5rem;
	z-index: 20;
}

.node-automation__canvas-search i {
	color: rgb(255 255 255 / 0.6);
	font-size: 1.1rem;
}

.node-automation__canvas-search input {
	background: transparent;
	border: none;
	color: #eee;
	font-size: 0.8rem;
	outline: none;
	width: 10rem;
}

.node-automation__canvas-search input::placeholder {
	color: rgb(255 255 255 / 0.35);
}

.node-automation__search-count {
	color: rgb(255 255 255 / 0.55);
	font-size: 0.75rem;
	min-width: 2.5rem;
	text-align: center;
	white-space: nowrap;
}

.node-automation__canvas-search button {
	align-items: center;
	background: transparent;
	border: none;
	border-radius: 3px;
	color: rgb(255 255 255 / 0.7);
	cursor: pointer;
	display: flex;
	font-size: 1rem;
	justify-content: center;
	padding: 0.15rem;
}

.node-automation__canvas-search button:hover {
	background: rgb(255 255 255 / 0.12);
}

.node-automation__subgraph-breadcrumb {
	align-items: center;
	background: rgb(15 15 15 / 0.9);
	border: 1px solid #7041a6;
	border-radius: 6px;
	color: #f2e8ff;
	display: flex;
	gap: 0.45rem;
	left: 0.75rem;
	padding: 0.35rem 0.55rem;
	position: sticky;
	top: 3.45rem;
	width: max-content;
	z-index: 4;
}

.node-automation__subgraph-breadcrumb button {
	align-items: center;
	background: #241333;
	border: 1px solid #7041a6;
	border-radius: 4px;
	color: #f2e8ff;
	cursor: pointer;
	display: flex;
	gap: 0.25rem;
	padding: 0.3rem 0.55rem;
}

.node-automation__subgraph-breadcrumb small {
	color: rgb(255 255 255 / 0.62);
}

.node-automation__wire-health {
	align-items: center;
	background: rgb(61 33 25 / 0.94);
	border: 1px solid rgb(239 154 154 / 0.5);
	border-radius: 6px;
	box-shadow: 0 12px 28px rgb(0 0 0 / 0.32);
	color: #fff4f4;
	display: grid;
	gap: 0.45rem;
	grid-template-columns: auto minmax(0, 1fr) auto auto;
	left: 0.75rem;
	max-width: min(42rem, calc(100% - 1.5rem));
	padding: 0.55rem 0.65rem;
	pointer-events: auto;
	position: sticky;
	top: 4.25rem;
	z-index: 22;
}

.node-automation__wire-health + .node-automation__wire-health {
	top: 7.35rem;
}

.node-automation__wire-health > i {
	color: #ef9a9a;
	font-size: 1.15rem;
}

.node-automation__wire-health div {
	display: grid;
	min-width: 0;
}

.node-automation__wire-health strong,
.node-automation__wire-health small {
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.node-automation__wire-health small {
	color: #ffd6d6;
	font-size: 0.72rem;
}

.node-automation__wire-health button {
	background: rgb(255 255 255 / 0.1);
	border: 1px solid rgb(255 255 255 / 0.18);
	border-radius: 4px;
	color: #fff;
	cursor: pointer;
	font-size: 0.72rem;
	font-weight: 700;
	padding: 0.25rem 0.5rem;
}

.node-automation__wire-health button:hover {
	background: rgb(239 83 80 / 0.32);
	border-color: rgb(239 154 154 / 0.72);
}
</style>
