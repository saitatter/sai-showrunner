<template>
	<div
		v-if="ghostNode"
		class="node-automation__ghost-node"
		:style="{
			transform: `translate(${ghostNode.x}px, ${ghostNode.y}px)`,
		}"
	>
		<i class="mdi mdi-plus" />
		<span>Drop here</span>
	</div>

	<div
		v-if="rubberBand"
		class="node-automation__rubber-band"
		:style="{
			transform: `translate(${rubberBand.x}px, ${rubberBand.y}px)`,
			width: `${rubberBand.width}px`,
			height: `${rubberBand.height}px`,
		}"
	/>
</template>

<script setup lang="ts">
import type { NodePosition } from "./useNodeCanvas"

defineProps<{
	ghostNode?: NodePosition | null
	rubberBand?: { x: number; y: number; width: number; height: number } | null
}>()
</script>

<style scoped>
.node-automation__rubber-band {
	background: rgb(139 53 230 / 0.12);
	border: 1.5px dashed #e9aaff;
	border-radius: 3px;
	pointer-events: none;
	position: absolute;
	z-index: 5;
}

.node-automation__ghost-node {
	align-items: center;
	background: rgb(139 53 230 / 0.18);
	border: 2px dashed #e9aaff;
	border-radius: 10px;
	color: #e9aaff;
	display: flex;
	font-size: 0.8rem;
	gap: 0.35rem;
	height: 74px;
	justify-content: center;
	opacity: 0.7;
	pointer-events: none;
	position: absolute;
	width: 220px;
	z-index: 4;
}
</style>
