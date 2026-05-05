<template>
	<svg class="node-automation__edges" :viewBox="viewBox" role="img" aria-label="Node connections">
		<path
			v-for="edge in flowEdges"
			:key="`${edge.id}:hit`"
			class="node-automation__edge-hit"
			:class="{ active: dropTargetEdgeId === edge.id }"
			:d="edge.path"
			vector-effect="non-scaling-stroke"
			@dragover.prevent.stop="dropTargetEdgeIdModel = edge.id"
			@dragleave.stop="onClearDropEdge(edge.id)"
			@drop.prevent.stop="onDropActionOnEdge($event, edge)"
			@pointerdown.stop="onStartExecEdgeDrag(edge.from, edge.port, $event)"
			@click.stop="onSelectFlowEdge(edge.id)"
		/>
		<path
			v-for="edge in flowEdges"
			:key="`${edge.id}:line`"
			class="node-automation__edge"
			:class="{ active: dropTargetEdgeId === edge.id, selected: selectedEdgeId === edge.id }"
			:d="edge.path"
			vector-effect="non-scaling-stroke"
		/>
		<g
			v-for="edge in labeledFlowEdges"
			:key="`${edge.id}:label`"
			class="node-automation__edge-label"
		>
			<rect
				:x="(edge.labelX ?? 0) - ((edge.labelWidth ?? 60) / 2)"
				:y="(edge.labelY ?? 0) - 11"
				:width="edge.labelWidth ?? 60"
				height="22"
				rx="11"
			/>
			<text
				:x="edge.labelX"
				:y="edge.labelY"
				text-anchor="middle"
				dominant-baseline="central"
			>{{ edge.label }}</text>
		</g>

		<path
			v-for="wire in dataWires"
			:key="`dw-hit:${wire.id}`"
			class="node-automation__data-wire-hit"
			:d="wire.path"
			vector-effect="non-scaling-stroke"
			@click.stop="onSelectDataWire(wire.id)"
		>
			<title>{{ dataWireTitle(wire) }}</title>
		</path>
		<path
			v-for="wire in dataWires"
			:key="`dw:${wire.id}`"
			class="node-automation__data-wire"
			:class="{ selected: selectedDataWireId === wire.id, removing: removingWireIds.has(wire.id), invalid: wire.valid === false }"
			:d="wire.path"
			:stroke="wire.color"
			vector-effect="non-scaling-stroke"
		>
			<title>{{ dataWireTitle(wire) }}</title>
		</path>

		<path
			v-if="dragWirePath"
			class="node-automation__data-wire node-automation__data-wire--dragging"
			:class="{ invalid: dragWirePath.valid === false }"
			:d="dragWirePath.path"
			:stroke="dragWirePath.color"
			vector-effect="non-scaling-stroke"
		>
			<title>{{ dragWirePath.validationMessage || "Release on a compatible input port to connect." }}</title>
		</path>

		<path
			v-if="execDragWirePath"
			class="node-automation__edge node-automation__edge--dragging"
			:d="execDragWirePath"
			vector-effect="non-scaling-stroke"
		/>

		<template v-for="(guide, gi) in alignmentGuides" :key="`guide-${gi}`">
			<line
				v-if="guide.axis === 'x'"
				class="node-automation__alignment-guide"
				:x1="guide.position"
				:y1="guide.from - 8"
				:x2="guide.position"
				:y2="guide.to + 8"
				vector-effect="non-scaling-stroke"
			/>
			<line
				v-else
				class="node-automation__alignment-guide"
				:x1="guide.from - 8"
				:y1="guide.position"
				:x2="guide.to + 8"
				:y2="guide.position"
				vector-effect="non-scaling-stroke"
			/>
		</template>
	</svg>
</template>

<script setup lang="ts">
import { computed } from "vue"
import type { EdgeData } from "./useNodeRendering"
import type { AlignmentGuide } from "./useNodeDrag"

interface DataWirePath {
	id: string
	path: string
	color: string
	fromNode: string
	fromPort: string
	toNode: string
	toPort: string
	valid?: boolean
	validationMessage?: string
}

interface DragWirePath {
	path: string
	color: string
	valid?: boolean
	validationMessage?: string
}

const props = defineProps<{
	viewBox: string
	flowEdges: EdgeData[]
	dataWires: DataWirePath[]
	dragWirePath?: DragWirePath | null
	execDragWirePath?: string
	alignmentGuides: AlignmentGuide[]
	dropTargetEdgeId?: string
	selectedEdgeId?: string
	selectedDataWireId?: string
	removingWireIds: Set<string>
	dataWireTitle: (wire: DataWirePath) => string
	onClearDropEdge: (edgeId: string) => void
	onDropActionOnEdge: (event: DragEvent, edge: EdgeData) => void
	onStartExecEdgeDrag: (nodeId: string, port: string | undefined, event: PointerEvent) => void
	onSelectFlowEdge: (edgeId: string) => void
	onSelectDataWire: (wireId: string) => void
}>()

const emit = defineEmits<{
	"update:dropTargetEdgeId": [value: string | undefined]
}>()

const dropTargetEdgeIdModel = computed({
	get: () => props.dropTargetEdgeId,
	set: (value: string | undefined) => emit("update:dropTargetEdgeId", value),
})

const labeledFlowEdges = computed(() => props.flowEdges.filter((item) => item.label))
</script>

<style scoped>
.node-automation__edges {
	inset: 0;
	min-height: 100%;
	min-width: 100%;
	position: absolute;
	z-index: 1;
}

.node-automation__edge {
	fill: none;
	stroke: #e9aaff;
	stroke-linecap: round;
	stroke-width: 2.5px;
}

.node-automation__edge--dragging {
	fill: none;
	stroke: #e9aaff;
	stroke-dasharray: 6 4;
	stroke-linecap: round;
	stroke-width: 2.5px;
	opacity: 0.7;
}

.node-automation__edge.active {
	stroke: #2ed47a;
	stroke-width: 4px;
}

.node-automation__edge.selected {
	stroke: #ffcc00;
	stroke-width: 3.5px;
}

.node-automation__edge-hit {
	fill: none;
	pointer-events: stroke;
	stroke: transparent;
	stroke-linecap: round;
	stroke-width: 22px;
}

.node-automation__edge-hit.active {
	stroke: rgb(46 212 122 / 0.15);
}

.node-automation__edge-label {
	pointer-events: none;
}

.node-automation__edge-label rect {
	fill: rgb(18 18 22 / 0.92);
	stroke: rgb(233 170 255 / 0.42);
	stroke-width: 1px;
}

.node-automation__edge-label text {
	fill: #f7e7ff;
	font-size: 0.72rem;
	font-weight: 700;
	letter-spacing: 0;
}

.node-automation__alignment-guide {
	pointer-events: none;
	stroke: #ff6b6b;
	stroke-dasharray: 4 3;
	stroke-width: 1px;
}

.node-automation__data-wire-hit {
	fill: none;
	pointer-events: stroke;
	stroke: transparent;
	stroke-linecap: round;
	stroke-width: 16px;
	cursor: pointer;
}

.node-automation__data-wire {
	fill: none;
	pointer-events: none;
	stroke-linecap: round;
	stroke-width: 2px;
}

.node-automation__data-wire.selected {
	stroke-width: 3.5px;
	filter: drop-shadow(0 0 4px currentColor);
}

.node-automation__data-wire.invalid {
	stroke-dasharray: 8 5;
	stroke-width: 3px;
	filter: drop-shadow(0 0 5px rgba(239, 83, 80, 0.6));
}

.node-automation__data-wire.removing {
	stroke: #ff4444;
	stroke-width: 3px;
	opacity: 0;
	transition: opacity 0.3s ease-out;
}

.node-automation__data-wire--dragging {
	stroke-dasharray: 6 4;
	opacity: 0.7;
	animation: wire-dash 0.4s linear infinite;
}

@keyframes wire-dash {
	to { stroke-dashoffset: -10; }
}
</style>
