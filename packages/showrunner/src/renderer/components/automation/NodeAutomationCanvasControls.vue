<template>
	<div class="node-automation__canvas-controls">
		<graph-toolbar-button icon="mdi mdi-magnify-minus-outline" label="Zoom out" @click="onSetZoom(zoom - zoomStep, true)" />
		<span>{{ Math.round(zoom * 100) }}%</span>
		<graph-toolbar-button icon="mdi mdi-magnify-plus-outline" label="Zoom in" @click="onSetZoom(zoom + zoomStep, true)" />
		<graph-toolbar-button icon="mdi mdi-fit-to-screen-outline" label="Fit graph" @click="onFitGraph()" />
		<graph-toolbar-button icon="mdi mdi-select-all" label="Fit selection" tooltip="Fit to selection" :disabled="selectedNodeCount < 1" @click="onFitSelection()" />
		<graph-toolbar-button icon="mdi mdi-backup-restore" label="Reset view" @click="onResetView()" />
		<graph-toolbar-button icon="mdi mdi-grid" label="Toggle snap to grid" :active="snapToGrid" @click="onToggleSnapToGrid()" />
		<graph-toolbar-button icon="mdi mdi-sitemap-outline" label="Auto-layout" @click="onAutoLayout()" />
		<graph-toolbar-button icon="mdi mdi-align-vertical-center" label="Align horizontally" tooltip="Align selected horizontally" :disabled="selectedNodeCount < 2" @click="onAlignSelectedNodes('horizontal')" />
		<graph-toolbar-button icon="mdi mdi-align-horizontal-center" label="Align vertically" tooltip="Align selected vertically" :disabled="selectedNodeCount < 2" @click="onAlignSelectedNodes('vertical')" />
		<graph-toolbar-button icon="mdi mdi-distribute-horizontal-center" label="Distribute evenly" tooltip="Distribute selected evenly" :disabled="selectedNodeCount < 3" @click="onDistributeSelectedNodes()" />
		<graph-toolbar-button icon="mdi mdi-vector-rectangle" label="Add annotation block" @click="onAddAnnotationBlock()" />
		<span class="node-automation__control-divider" />
		<graph-toolbar-button
			:icon="isPreviewPlaying ? 'mdi mdi-pause' : 'mdi mdi-play'"
			:label="isPreviewPlaying ? 'Pause preview playhead' : 'Play preview playhead'"
			@click="onTogglePlayheadPreview()"
		/>
		<graph-toolbar-button icon="mdi mdi-stop" label="Reset preview playhead" @click="onResetPlayheadPreview()" />
		<div class="node-automation__preview-status">
			<div class="node-automation__preview-meter">
				<span :style="{ width: `${playheadProgress}%` }" />
			</div>
			<strong>{{ currentPreviewTitle || "Preview idle" }}</strong>
			<small>
				<span v-if="currentPreviewRouteLabel">{{ currentPreviewRouteLabel }} - </span>{{ playheadElapsedLabel }} / {{ previewTotalLabel }}
			</small>
		</div>
	</div>
</template>

<script setup lang="ts">
import { GraphToolbarButton } from "showrunner-ui-core"

defineProps<{
	zoom: number
	zoomStep: number
	snapToGrid: boolean
	selectedNodeCount: number
	isPreviewPlaying: boolean
	playheadProgress: number
	currentPreviewTitle?: string
	currentPreviewRouteLabel?: string
	playheadElapsedLabel: string
	previewTotalLabel: string
	onSetZoom: (zoom: number, commit?: boolean) => void
	onFitGraph: () => void
	onFitSelection: () => void
	onResetView: () => void
	onToggleSnapToGrid: () => void
	onAutoLayout: () => void
	onAlignSelectedNodes: (axis: "horizontal" | "vertical") => void
	onDistributeSelectedNodes: () => void
	onAddAnnotationBlock: () => void
	onTogglePlayheadPreview: () => void
	onResetPlayheadPreview: () => void
}>()
</script>

<style scoped>
.node-automation__canvas-controls {
	align-items: center;
	background: rgb(15 15 15 / 0.88);
	border: 1px solid #454545;
	border-radius: 6px;
	display: flex;
	gap: 0.35rem;
	left: 0.75rem;
	padding: 0.35rem;
	position: sticky;
	top: 0.75rem;
	width: max-content;
	z-index: 4;
}

.node-automation__canvas-controls button {
	align-items: center;
	background: #2b173d;
	border: 1px solid #7041a6;
	border-radius: 4px;
	color: var(--text-color);
	cursor: pointer;
	display: flex;
	height: 2rem;
	justify-content: center;
	width: 2rem;
}

.node-automation__canvas-controls button.active {
	background: #8b35e6;
	border-color: #e9aaff;
}

.node-automation__canvas-controls button:disabled {
	cursor: not-allowed;
	opacity: 0.45;
}

.node-automation__canvas-controls span {
	color: #e9e9e9;
	font-size: 0.8rem;
	min-width: 3rem;
	text-align: center;
}

.node-automation__canvas-controls .node-automation__control-divider {
	background: #454545;
	display: block;
	height: 1.35rem;
	min-width: 1px;
	width: 1px;
}

.node-automation__preview-status {
	align-items: center;
	background: rgb(0 0 0 / 0.28);
	border: 1px solid rgb(255 255 255 / 0.12);
	border-radius: 4px;
	display: grid;
	gap: 0.15rem;
	grid-template-columns: 8rem minmax(6rem, 1fr) auto;
	min-width: 20rem;
	padding: 0.35rem 0.5rem;
}

.node-automation__preview-status strong,
.node-automation__preview-status small {
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.node-automation__preview-status strong {
	font-size: 0.76rem;
}

.node-automation__preview-status small {
	color: #d6d6d6;
	font-size: 0.7rem;
	justify-self: end;
}

.node-automation__preview-meter {
	background: #101010;
	border: 1px solid rgb(255 255 255 / 0.12);
	border-radius: 999px;
	height: 0.42rem;
	overflow: hidden;
}

.node-automation__preview-meter span {
	background: linear-gradient(90deg, #e9aaff, #2ed47a);
	display: block;
	height: 100%;
	min-width: 0;
	transition: width 90ms linear;
}
</style>
