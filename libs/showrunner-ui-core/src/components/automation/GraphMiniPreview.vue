<template>
	<div class="graph-mini-preview" :class="{ empty: nodeCount === 0 }">
		<span class="graph-mini-preview__icon">
			<i class="mdi mdi-graph-outline" />
		</span>
		<span class="graph-mini-preview__body">
			<strong>{{ label }}</strong>
			<small>{{ detail }}</small>
		</span>
	</div>
</template>

<script setup lang="ts">
import { computed } from "vue"
import type { AutomationGraph } from "ShowRunner-schema"

const props = defineProps<{
	graph?: AutomationGraph
}>()

const nodeCount = computed(() => props.graph?.nodes?.length ?? 0)
const edgeCount = computed(() => props.graph?.edges?.length ?? 0)

const label = computed(() => (nodeCount.value > 0 ? `${nodeCount.value} graph node${nodeCount.value === 1 ? "" : "s"}` : "Empty graph"))
const detail = computed(() => {
	if (nodeCount.value === 0) return "Add triggers and actions in the node graph editor."
	return `${edgeCount.value} connection${edgeCount.value === 1 ? "" : "s"}`
})
</script>

<style scoped>
.graph-mini-preview {
	display: flex;
	align-items: center;
	gap: 0.5rem;
	width: 100%;
	min-height: 2.4rem;
	color: var(--text-color);
}

.graph-mini-preview.empty {
	color: var(--text-color-secondary);
}

.graph-mini-preview__icon {
	display: inline-flex;
	align-items: center;
	justify-content: center;
	width: 1.8rem;
	height: 1.8rem;
	border-radius: 6px;
	background: rgba(170, 93, 255, 0.16);
	color: #d58cff;
}

.graph-mini-preview__body {
	display: grid;
	gap: 0.1rem;
	min-width: 0;
}

.graph-mini-preview__body strong,
.graph-mini-preview__body small {
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.graph-mini-preview__body small {
	color: var(--text-color-secondary);
	font-size: 0.78rem;
}
</style>
