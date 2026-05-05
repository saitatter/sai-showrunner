<template>
	<div class="subgraph-panel">
		<ul v-if="subgraphs.length" class="subgraph-panel__list">
			<li
				v-for="sg in subgraphs"
				:key="sg.id"
				class="subgraph-panel__item"
				:class="{ focused: focusedSubgraphId === sg.id }"
			>
				<label class="subgraph-panel__name">
					<i class="mdi mdi-function" />
					<input
						type="text"
						:value="sg.name"
						placeholder="Subgraph name"
						@change="onUpdateSubgraphName(sg.id, ($event.target as HTMLInputElement).value)"
					/>
				</label>
				<span class="subgraph-panel__meta">
					{{ sg.parameters.length }} param{{ sg.parameters.length === 1 ? '' : 's' }},
					{{ sg.outputs.length }} output{{ sg.outputs.length === 1 ? '' : 's' }},
					{{ sg.nodes.length }} node{{ sg.nodes.length === 1 ? '' : 's' }}
				</span>
				<div class="subgraph-panel__tools">
					<button type="button" title="Open subgraph canvas" @click="onOpenSubgraphCanvas(sg.id)">
						<i class="mdi mdi-open-in-app" /> Open
					</button>
					<button type="button" title="Focus subgraph details" @click="onFocusSubgraph(sg.id)">
						<i class="mdi mdi-crosshairs-gps" /> Focus
					</button>
					<button type="button" title="Add a call node for this subgraph" @click="onAddSubgraphCallNode(sg.id)">
						<i class="mdi mdi-plus-box-outline" /> Call
					</button>
				</div>
				<div class="subgraph-panel__params">
					<strong>Inputs</strong>
					<div v-for="(param, pi) in sg.parameters" :key="`in-${sg.id}-${pi}`">
						<input :value="param.name" placeholder="name" @change="onUpdateSubgraphParam(sg.id, 'parameters', pi, 'name', ($event.target as HTMLInputElement).value)" />
						<select :value="param.type" @change="onUpdateSubgraphParam(sg.id, 'parameters', pi, 'type', ($event.target as HTMLSelectElement).value)">
							<option v-for="type in subgraphParamTypes" :key="type" :value="type">{{ type }}</option>
						</select>
						<input :value="String(param.default ?? '')" placeholder="default" @change="onUpdateSubgraphParam(sg.id, 'parameters', pi, 'default', ($event.target as HTMLInputElement).value)" />
						<button type="button" class="danger" @click="onDeleteSubgraphParam(sg.id, 'parameters', pi)"><i class="mdi mdi-close" /></button>
					</div>
					<button type="button" @click="onAddSubgraphParam(sg.id, 'parameters')"><i class="mdi mdi-plus" /> Input</button>
					<strong>Outputs</strong>
					<div v-for="(param, pi) in sg.outputs" :key="`out-${sg.id}-${pi}`">
						<input :value="param.name" placeholder="name" @change="onUpdateSubgraphParam(sg.id, 'outputs', pi, 'name', ($event.target as HTMLInputElement).value)" />
						<select :value="param.type" @change="onUpdateSubgraphParam(sg.id, 'outputs', pi, 'type', ($event.target as HTMLSelectElement).value)">
							<option v-for="type in subgraphParamTypes" :key="type" :value="type">{{ type }}</option>
						</select>
						<button type="button" class="danger" @click="onDeleteSubgraphParam(sg.id, 'outputs', pi)"><i class="mdi mdi-close" /></button>
					</div>
					<button type="button" @click="onAddSubgraphParam(sg.id, 'outputs')"><i class="mdi mdi-plus" /> Output</button>
				</div>
				<button type="button" class="danger subgraph-panel__delete" title="Delete subgraph" @click="onDeleteSubgraph(sg.id)">
					<i class="mdi mdi-trash-can-outline" />
				</button>
			</li>
		</ul>
		<p v-else class="subgraph-panel__hint">No subgraphs defined.</p>
		<button type="button" class="subgraph-panel__add" @click="onAddSubgraph()">
			<i class="mdi mdi-plus" /> New Subgraph
		</button>
	</div>
</template>

<script setup lang="ts">
import type { SubgraphDefinition, SubgraphParamType } from "showrunner-schema"

defineProps<{
	subgraphs: SubgraphDefinition[]
	subgraphParamTypes: SubgraphParamType[]
	focusedSubgraphId?: string
	onAddSubgraph: () => void
	onFocusSubgraph: (id: string) => void
	onOpenSubgraphCanvas: (id: string) => void
	onDeleteSubgraph: (id: string) => void
	onUpdateSubgraphName: (id: string, name: string) => void
	onAddSubgraphParam: (id: string, collection: "parameters" | "outputs") => void
	onDeleteSubgraphParam: (id: string, collection: "parameters" | "outputs", index: number) => void
	onUpdateSubgraphParam: (
		id: string,
		collection: "parameters" | "outputs",
		index: number,
		field: "name" | "type" | "default",
		value: string
	) => void
	onAddSubgraphCallNode: (subgraphId: string) => void
}>()
</script>

<style scoped>
.subgraph-panel {
	padding: 0.65rem;
}

.subgraph-panel__list {
	display: grid;
	gap: 0.4rem;
	list-style: none;
	margin: 0 0 0.5rem;
	padding: 0;
}

.subgraph-panel__item {
	align-items: center;
	background: #101010;
	border: 1px solid #303030;
	border-radius: 4px;
	display: grid;
	gap: 0.2rem;
	grid-template-columns: 1fr auto;
	padding: 0.5rem 0.6rem;
}

.subgraph-panel__item.focused {
	border-color: #e9aaff;
	box-shadow: 0 0 0 1px rgba(233, 170, 255, 0.25);
}

.subgraph-panel__name {
	align-items: center;
	display: flex;
	gap: 0.45rem;
	font-weight: 500;
}

.subgraph-panel__name input,
.subgraph-panel__params input,
.subgraph-panel__params select {
	background: #070707;
	border: 1px solid #333;
	border-radius: 4px;
	color: #eee;
	min-width: 0;
	padding: 0.35rem 0.45rem;
}

.subgraph-panel__name input {
	width: 100%;
}

.subgraph-panel__meta {
	color: #999;
	font-size: 0.75rem;
	grid-column: 1;
}

.subgraph-panel__tools {
	display: flex;
	flex-wrap: wrap;
	gap: 0.35rem;
	grid-column: 1 / -1;
}

.subgraph-panel__tools button,
.subgraph-panel__params button {
	background: #1e1e1e;
	border: 1px solid #3b3b3b;
	border-radius: 4px;
	color: #ddd;
	cursor: pointer;
	padding: 0.35rem 0.5rem;
}

.subgraph-panel__params {
	display: grid;
	gap: 0.35rem;
	grid-column: 1 / -1;
	margin-top: 0.35rem;
}

.subgraph-panel__params > div {
	display: grid;
	gap: 0.35rem;
	grid-template-columns: minmax(0, 1fr) 6.5rem minmax(0, 1fr) auto;
}

.subgraph-panel__params strong {
	color: #ddd;
	font-size: 0.75rem;
	margin-top: 0.25rem;
	text-transform: uppercase;
}

.subgraph-panel__delete {
	background: transparent;
	border: none;
	color: #ef5350;
	cursor: pointer;
	grid-column: 2;
	grid-row: 1 / 3;
	padding: 0.3rem;
}

.subgraph-panel__add {
	background: #1e1e1e;
	border: 1px dashed #555;
	border-radius: 4px;
	color: #ccc;
	cursor: pointer;
	padding: 0.5rem;
	width: 100%;
}

.subgraph-panel__add:hover {
	background: #2a2a2a;
	border-color: #e9aaff;
	color: #fff;
}

.subgraph-panel__hint {
	color: #cfcfcf;
	line-height: 1.45;
	margin: 0;
}
</style>
