<template>
	<div
		v-for="block in blocks"
		:key="block.id"
		class="node-automation__annotation-block"
		:class="{ selected: selectedBlockId === block.id, 'drop-target': dropTargetBlockId === block.id }"
		:style="annotationBlockStyle(block)"
		@pointerdown.stop="onStartAnnotationBlockDrag($event, block)"
		@click.stop="onSelectAnnotationBlock(block.id)"
	>
		<span>{{ block.label || "Annotation" }}</span>
		<small v-if="block.nodeIds?.length">{{ block.nodeIds.length }} node{{ block.nodeIds.length === 1 ? '' : 's' }}</small>
		<button
			type="button"
			class="node-automation__annotation-resize"
			title="Resize annotation block"
			@pointerdown.stop="onStartAnnotationBlockResize($event, block)"
		/>
	</div>
</template>

<script setup lang="ts">
import type { StyleValue } from "vue"
import type { AnnotationBlock } from "./useAnnotationBlocks"

defineProps<{
	blocks: AnnotationBlock[]
	selectedBlockId?: string
	dropTargetBlockId?: string
	annotationBlockStyle: (block: AnnotationBlock) => StyleValue
	onStartAnnotationBlockDrag: (event: PointerEvent, block: AnnotationBlock) => void
	onStartAnnotationBlockResize: (event: PointerEvent, block: AnnotationBlock) => void
	onSelectAnnotationBlock: (blockId: string) => void
}>()
</script>

<style scoped>
.node-automation__annotation-block {
	border: 2px dashed;
	border-radius: 6px;
	box-sizing: border-box;
	cursor: move;
	position: absolute;
	z-index: 2;
}

.node-automation__annotation-block.selected {
	border-style: solid;
	box-shadow: 0 0 0 2px rgb(255 255 255 / 0.16);
}

.node-automation__annotation-block.drop-target {
	border-style: solid;
	box-shadow: 0 0 0 3px rgb(46 212 122 / 0.38);
}

.node-automation__annotation-block span {
	background: rgb(16 16 16 / 0.9);
	border: 1px solid rgb(255 255 255 / 0.14);
	border-radius: 4px;
	color: #f4f4f4;
	font-size: 0.75rem;
	font-weight: 700;
	left: 0.65rem;
	letter-spacing: 0;
	max-width: calc(100% - 2rem);
	overflow: hidden;
	padding: 0.18rem 0.45rem;
	position: absolute;
	text-overflow: ellipsis;
	top: 0.45rem;
	white-space: nowrap;
}

.node-automation__annotation-block small {
	background: rgb(16 16 16 / 0.82);
	border: 1px solid rgb(255 255 255 / 0.14);
	border-radius: 999px;
	bottom: 0.45rem;
	color: #dbeafe;
	font-size: 0.68rem;
	font-weight: 700;
	left: 0.65rem;
	padding: 0.15rem 0.45rem;
	position: absolute;
}

.node-automation__annotation-resize {
	background: rgb(16 16 16 / 0.72);
	border: 1px solid rgb(255 255 255 / 0.18);
	border-radius: 3px;
	bottom: 0.35rem;
	cursor: nwse-resize;
	height: 0.9rem;
	position: absolute;
	right: 0.35rem;
	width: 0.9rem;
}

.node-automation__annotation-resize::after {
	border-bottom: 2px solid rgb(255 255 255 / 0.65);
	border-right: 2px solid rgb(255 255 255 / 0.65);
	bottom: 0.18rem;
	content: "";
	height: 0.38rem;
	position: absolute;
	right: 0.18rem;
	width: 0.38rem;
}
</style>
