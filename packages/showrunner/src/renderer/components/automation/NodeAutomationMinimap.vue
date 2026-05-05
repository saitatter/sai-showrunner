<template>
	<svg
		class="node-automation__minimap"
		:viewBox="viewBox"
		preserveAspectRatio="xMidYMid meet"
		@pointerdown.stop="onPointerDown"
	>
		<rect
			v-for="node in nodes"
			:key="`mm-${node.id}`"
			:x="node.x"
			:y="node.y"
			:width="node.width ?? nodeWidth"
			:height="node.height"
			:class="`node-automation__minimap-node--${node.kind}`"
			rx="3"
		/>
		<path
			v-for="edge in edges"
			:key="`mm-${edge.id}`"
			:d="edge.path"
			class="node-automation__minimap-edge"
			fill="none"
		/>
		<path
			v-for="wire in dataWires"
			:key="`mm-dw-${wire.id}`"
			:d="wire.path"
			class="node-automation__minimap-data-wire"
			:stroke="wire.color"
			fill="none"
		/>
		<rect
			class="node-automation__minimap-viewport"
			:x="viewport.x"
			:y="viewport.y"
			:width="viewport.width"
			:height="viewport.height"
			rx="2"
		/>
	</svg>
</template>

<script setup lang="ts">
import type { EdgeData, NodeData } from "./useNodeRendering"

interface DataWirePath {
	id: string
	path: string
	color: string
}

defineProps<{
	nodes: NodeData[]
	edges: EdgeData[]
	dataWires: DataWirePath[]
	viewBox: string
	viewport: { x: number; y: number; width: number; height: number }
	nodeWidth: number
	onPointerDown: (event: PointerEvent) => void
}>()
</script>

<style scoped>
.node-automation__minimap {
	background: rgb(0 0 0 / 0.5);
	border: 1px solid rgb(255 255 255 / 0.12);
	border-radius: 4px;
	bottom: 0.75rem;
	cursor: crosshair;
	float: right;
	height: 120px;
	pointer-events: auto;
	position: sticky;
	width: 180px;
	z-index: 18;
}

.node-automation__minimap-node--trigger { fill: #4fc3f7; }
.node-automation__minimap-node--action { fill: #81c784; }
.node-automation__minimap-node--conversion { fill: #4dd0e1; }
.node-automation__minimap-node--queue { fill: #ffcf5a; }
.node-automation__minimap-node--stack { fill: #ba68c8; }
.node-automation__minimap-node--time { fill: #ffb74d; }
.node-automation__minimap-node--flow { fill: #4dd0e1; }
.node-automation__minimap-node--floating { fill: #a1887f; }
.node-automation__minimap-node--variable { fill: #90a4ae; }
.node-automation__minimap-node--if { fill: #64b5f6; }
.node-automation__minimap-node--switch { fill: #7c4dff; }
.node-automation__minimap-node--for,
.node-automation__minimap-node--forEach { fill: #68d391; }
.node-automation__minimap-node--while { fill: #4db6ac; }
.node-automation__minimap-node--break,
.node-automation__minimap-node--continue { fill: #ef9a9a; }
.node-automation__minimap-node--return { fill: #ffab91; }

.node-automation__minimap-edge {
	stroke: rgb(255 255 255 / 0.25);
	stroke-width: 1.5;
}

.node-automation__minimap-data-wire {
	stroke-width: 1;
	opacity: 0.6;
}

.node-automation__minimap-viewport {
	fill: rgb(255 255 255 / 0.08);
	stroke: rgb(255 255 255 / 0.55);
	stroke-width: 2;
	vector-effect: non-scaling-stroke;
}
</style>
