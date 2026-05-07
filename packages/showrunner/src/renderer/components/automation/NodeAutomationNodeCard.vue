<template>
	<button
		class="node-automation__node"
		:data-graph-node-id="node.id"
		:class="[
			`node-automation__node--${node.kind}`,
			{
				selected,
				'annotation-member': annotationMember,
				missing: node.missing,
				'drop-target': dropTarget,
				'preview-active': previewActive,
				'search-match': searchMatch,
				'search-dimmed': searchDimmed,
				'test-running': activeTestExecution?.activeIds?.[node.id] != null,
				'test-success': !activeTestExecution?.activeIds?.[node.id] && activeTestExecution?.nodeResults?.[node.id] != null && !activeTestExecution?.nodeErrors?.[node.id],
				'test-error': !!activeTestExecution?.nodeErrors?.[node.id],
			},
		]"
		:style="{ transform: `translate(${node.x}px, ${node.y}px)`, height: `${node.height}px`, width: `${node.width ?? nodeWidth}px` }"
		type="button"
		role="treeitem"
		:aria-selected="selected"
		:aria-label="`${node.kind} node: ${node.title} - ${node.subtitle}`"
		tabindex="0"
		@pointerdown.stop="onStartDrag($event, node)"
		@click.stop="onSelectNode($event, node.id)"
		@dblclick.stop="onOpenSubgraphFromNode(node.id)"
		@contextmenu.prevent.stop="onOpenNodeContext($event, node)"
		@dragover.prevent.stop="onSetDropTargetNodeId(node.id)"
		@dragleave.stop="onClearDropTarget(node.id)"
		@drop.prevent.stop="onDropActionOnNode($event, node)"
	>
		<span
			v-if="node.kind !== 'variable' && node.kind !== 'conversion'"
			class="node-automation__handle node-automation__handle--in"
			:class="{ 'connectable': activeGraph }"
		/>
		<span class="node-automation__node-icon">
			<i :class="node.icon" />
		</span>
		<span class="node-automation__node-text">
			<strong>{{ node.title }}</strong>
			<small
				v-if="node.kind === 'variable' && inlineEditNodeId === node.id"
				class="node-automation__inline-edit"
			>
				<input
					ref="inlineEditInput"
					type="text"
					:value="node.subtitle"
					@blur="onCommitInlineEdit($event, node)"
					@keydown.enter="($event.target as HTMLInputElement).blur()"
					@keydown.escape="onCancelInlineEdit()"
					@pointerdown.stop
					@click.stop
				/>
			</small>
			<small
				v-else
				@dblclick.stop="node.kind === 'variable' && onStartInlineEdit(node.id)"
			>{{ node.subtitle }}</small>
		</span>
		<span v-if="node.kind === 'trigger'" class="node-automation__node-run" title="Run automation" @click.stop="onRunMainExecution()" v-tooltip="'Run automation'">
			<i class="mdi mdi-play" />
		</span>
		<span v-if="node.badge" class="node-automation__node-badge">{{ node.badge }}</span>
		<span
			v-if="activeTestExecution?.nodeErrors?.[node.id]"
			class="node-automation__test-badge node-automation__test-badge--error"
			:title="activeTestExecution.nodeErrors?.[node.id]"
		><i class="mdi mdi-close" /></span>
		<span
			v-else-if="activeTestExecution?.nodeResults?.[node.id] != null"
			class="node-automation__test-badge node-automation__test-badge--ok"
			:title="JSON.stringify(activeTestExecution.nodeResults[node.id], null, 2)"
		><i class="mdi mdi-check" /></span>
		<span
			v-if="activeTestExecution?.nodeDurations?.[node.id] != null"
			class="node-automation__test-duration"
			:title="`Last test-run duration: ${formatNodeDuration(activeTestExecution.nodeDurations[node.id])}`"
		>{{ formatNodeDuration(activeTestExecution.nodeDurations[node.id]) }}</span>
		<dl v-if="node.configLines?.length" class="node-automation__node-config">
			<div v-for="(line, li) in node.configLines" :key="li" class="node-automation__node-config-line">
				<dt>{{ line.label }}</dt>
				<dd>{{ line.value }}</dd>
			</div>
		</dl>
		<div v-if="node.inputPorts?.length || node.outputPorts?.length" class="node-automation__node-ports">
			<div class="node-automation__port-columns">
				<ul v-if="node.inputPorts?.length" class="node-automation__port-list node-automation__port-list--in">
					<li v-for="port in node.inputPorts" :key="port.key" class="node-automation__port node-automation__port--in">
						<span
							class="node-automation__port-dot node-automation__port-dot--in"
							:class="[{ connected: isPortConnected(node.id, port.key, 'in') }, dataPortDragClass(node.id, port.key, 'in')]"
							:data-port-node-id="node.id"
							:data-port-key="port.key"
							data-port-kind="in"
							:data-port-type="port.type"
							:title="dataPortDragTitle(node.id, port.key, 'in')"
							:style="portStyle(port.type, isPortConnected(node.id, port.key, 'in'))"
							@pointerdown.stop="onStartWireDrag(node.id, port.key, 'in', $event)"
						/>
						<span class="node-automation__port-label">{{ port.label }}</span>
						<span class="node-automation__port-type">{{ port.type }}</span>
					</li>
				</ul>
				<ul v-if="node.outputPorts?.length" class="node-automation__port-list node-automation__port-list--out">
					<li v-for="port in node.outputPorts" :key="port.key" class="node-automation__port node-automation__port--out">
						<span class="node-automation__port-type">{{ port.type }}</span>
						<span class="node-automation__port-label">{{ port.label }}</span>
						<span
							v-if="port.type === 'flow'"
							class="node-automation__port-dot node-automation__port-dot--out node-automation__port-dot--exec"
							:class="{ connected: isExecPortConnected(node.id, port.key) }"
							:data-port-node-id="node.id"
							:data-port-key="port.key"
							data-port-kind="out"
							:data-port-type="port.type"
							@pointerdown.stop="onStartExecEdgeDrag(node.id, port.key, $event)"
						/>
						<span
							v-else
							class="node-automation__port-dot node-automation__port-dot--out"
							:class="[{ connected: isPortConnected(node.id, port.key, 'out') }, dataPortDragClass(node.id, port.key, 'out')]"
							:data-port-node-id="node.id"
							:data-port-key="port.key"
							data-port-kind="out"
							:data-port-type="port.type"
							:title="dataPortDragTitle(node.id, port.key, 'out')"
							:style="portStyle(port.type, isPortConnected(node.id, port.key, 'out'))"
							@pointerdown.stop="onStartWireDrag(node.id, port.key, 'out', $event)"
						/>
					</li>
				</ul>
			</div>
		</div>
		<span
			v-if="canStartFlow"
			class="node-automation__handle node-automation__handle--out"
			:class="{ 'connectable': activeGraph }"
			title="Drag to connect to another node"
			@pointerdown.stop="activeGraph && onStartExecEdgeDrag(node.id, undefined, $event)"
		/>
		<span
			class="node-automation__resize-handle"
			title="Resize node"
			@pointerdown.stop="onStartResize($event, node)"
		/>
	</button>
</template>

<script setup lang="ts">
import { nextTick, ref, watch } from "vue"
import { portTypeColor } from "./usePortConnections"
import type { NodeData } from "./useNodeRendering"

type PortKind = "in" | "out"

interface ActiveTestExecution {
	activeIds?: Record<string, unknown>
	nodeResults?: Record<string, unknown>
	nodeErrors?: Record<string, string>
	nodeDurations?: Record<string, number>
}

const props = defineProps<{
	node: NodeData
	nodeWidth: number
	selected: boolean
	annotationMember: boolean
	dropTarget: boolean
	previewActive: boolean
	searchMatch: boolean
	searchDimmed: boolean
	activeGraph: boolean
	canStartFlow: boolean
	inlineEditNodeId?: string
	activeTestExecution?: ActiveTestExecution
	isPortConnected: (nodeId: string, portKey: string, kind: PortKind) => boolean
	isExecPortConnected: (nodeId: string, portKey: string) => boolean
	dataPortDragClass: (nodeId: string, portKey: string, kind: PortKind) => string | undefined
	dataPortDragTitle: (nodeId: string, portKey: string, kind: PortKind) => string | undefined
	formatNodeDuration: (durationMs: number) => string
	onStartDrag: (event: PointerEvent, node: NodeData) => void
	onSelectNode: (event: MouseEvent | PointerEvent, nodeId: string) => void
	onOpenSubgraphFromNode: (nodeId: string) => void
	onOpenNodeContext: (event: MouseEvent, node: NodeData) => void
	onSetDropTargetNodeId: (nodeId: string) => void
	onClearDropTarget: (nodeId: string) => void
	onDropActionOnNode: (event: DragEvent, node: NodeData) => void
	onStartInlineEdit: (nodeId: string) => void
	onCommitInlineEdit: (event: Event, node: NodeData) => void
	onCancelInlineEdit: () => void
	onRunMainExecution: () => void
	onStartWireDrag: (nodeId: string, portKey: string, kind: PortKind, event: PointerEvent) => void
	onStartExecEdgeDrag: (nodeId: string, portKey: string | undefined, event: PointerEvent) => void
	onStartResize: (event: PointerEvent, node: NodeData) => void
}>()

const inlineEditInput = ref<HTMLInputElement>()

watch(
	() => props.inlineEditNodeId === props.node.id,
	(active) => {
		if (!active) return
		nextTick(() => {
			inlineEditInput.value?.focus()
			inlineEditInput.value?.select()
		})
	},
	{ immediate: true }
)

function portStyle(type: string, connected: boolean) {
	const color = portTypeColor(type)
	return {
		borderColor: color,
		background: connected ? color : `${color}44`,
	}
}
</script>

<style scoped>
.node-automation__node {
	align-items: center;
	background: #181818;
	border: 2px solid #7d32d4;
	border-radius: 6px;
	box-shadow: 0 10px 24px rgb(0 0 0 / 0.28);
	color: white;
	cursor: grab;
	display: grid;
	gap: 0.45rem 0.65rem;
	grid-template-columns: 2rem minmax(0, 1fr) auto;
	grid-template-rows: auto;
	min-height: 74px;
	padding: 0.7rem;
	position: absolute;
	text-align: left;
	touch-action: none;
	z-index: 2;
}

.node-automation__handle {
	background: #111;
	border: 2px solid #e9aaff;
	border-radius: 999px;
	height: 0.85rem;
	position: absolute;
	top: 50%;
	transform: translateY(-50%);
	width: 0.85rem;
}

.node-automation__handle--in {
	left: -0.5rem;
}

.node-automation__handle--out {
	right: -0.5rem;
}

.node-automation__handle.connectable {
	cursor: crosshair;
	transition: background 0.15s, border-color 0.15s, transform 0.15s;
}

.node-automation__handle.connectable:hover {
	background: #e9aaff;
	border-color: #fff;
	transform: translateY(-50%) scale(1.3);
}

.node-automation__node.drop-target .node-automation__handle--out {
	background: #2ed47a;
	border-color: #d2ffe3;
}

.node-automation__node:active {
	cursor: grabbing;
}

.node-automation__node.selected {
	border-color: #ffdf6b;
	box-shadow: 0 0 0 3px rgb(255 223 107 / 0.2), 0 12px 28px rgb(0 0 0 / 0.35);
}

.node-automation__node.annotation-member:not(.selected) {
	box-shadow: 0 0 0 2px rgb(100 181 246 / 0.42), 0 10px 24px rgb(0 0 0 / 0.28);
}

.node-automation__node:focus-visible {
	outline: 2px solid #80bdff;
	outline-offset: 2px;
}

.node-automation__node.preview-active {
	border-color: #2ed47a;
	box-shadow: 0 0 0 4px rgb(46 212 122 / 0.28), 0 0 30px rgb(46 212 122 / 0.22), 0 12px 28px rgb(0 0 0 / 0.35);
}

.node-automation__node.search-dimmed {
	opacity: 0.3;
}

.node-automation__node.search-match {
	box-shadow: 0 0 0 2px #ffcc00;
}

.node-automation__node.test-running {
	border-color: #4fc3f7;
	box-shadow: 0 0 0 3px rgb(79 195 247 / 0.3), 0 0 20px rgb(79 195 247 / 0.15);
	animation: pulse-border 0.8s ease-in-out infinite alternate;
}

.node-automation__node.test-success {
	border-color: #66bb6a;
	box-shadow: 0 0 0 2px rgb(102 187 106 / 0.25);
}

.node-automation__node.test-error {
	border-color: #ef5350;
	box-shadow: 0 0 0 2px rgb(239 83 80 / 0.3), 0 0 12px rgb(239 83 80 / 0.2);
}

.node-automation__node.missing {
	background: #2a1717;
	border-color: #ef5350;
	box-shadow: 0 0 0 2px rgb(239 83 80 / 0.16);
}

@keyframes pulse-border {
	from { opacity: 0.7; }
	to { opacity: 1; }
}

.node-automation__node.drop-target {
	border-color: #2ed47a;
	box-shadow: 0 0 0 4px rgb(46 212 122 / 0.22), 0 12px 28px rgb(0 0 0 / 0.35);
}

.node-automation__node--trigger {
	background: #40256c;
	border-color: #e9aaff;
}

.node-automation__node--action {
	background: #151515;
	border-color: #7d32d4;
}

.node-automation__node--conversion {
	background: color-mix(in srgb, #4dd0e1 10%, #151515);
	border-color: #4dd0e1;
}

.node-automation__node--queue {
	background: color-mix(in srgb, #ffcf5a 12%, #151515);
	border-color: #ffcf5a;
}

.node-automation__node--time {
	border-color: #68d391;
}

.node-automation__node--flow {
	border-color: #64b5f6;
}

.node-automation__node--if {
	border-color: #64b5f6;
}

.node-automation__node--switch {
	border-color: #7c4dff;
}

.node-automation__node--for,
.node-automation__node--forEach {
	border-color: #68d391;
}

.node-automation__node--while {
	border-color: #4db6ac;
}

.node-automation__node--break,
.node-automation__node--continue {
	border-color: #ef9a9a;
}

.node-automation__node--return {
	border-color: #ffab91;
}

.node-automation__node--floating {
	border-color: #ff9bd7;
}

.node-automation__node--variable {
	background: linear-gradient(135deg, rgb(38 50 56 / 0.96), rgb(20 28 31 / 0.96));
	border-color: #90a4ae;
	border-radius: 6px;
	border-style: dashed;
	box-shadow: inset 0 0 0 1px rgb(255 255 255 / 0.06), 0 8px 20px rgb(0 0 0 / 0.3);
	min-width: 150px;
	padding-left: 0.85rem;
	padding-right: 0.85rem;
}

.node-automation__node--variable::before {
	background: currentColor;
	border-radius: 999px;
	content: "";
	height: calc(100% - 1.2rem);
	left: 0.45rem;
	opacity: 0.28;
	position: absolute;
	top: 0.6rem;
	width: 0.22rem;
}

.node-automation__node--variable .node-automation__node-icon {
	background: rgb(255 255 255 / 0.16);
	border-radius: 999px;
}

.node-automation__node--variable .node-automation__node-badge {
	background: rgb(144 164 174 / 0.25);
	border: 1px solid rgb(144 164 174 / 0.45);
	color: #d9edf4;
}

.node-automation__node--trigger .node-automation__node-badge {
	background: #ffdf6b;
}

.node-automation__node.missing .node-automation__node-badge {
	background: #ef5350;
	color: #fff;
}

.node-automation__node-icon {
	align-items: center;
	background: rgb(255 255 255 / 0.12);
	border-radius: 4px;
	display: flex;
	font-size: 1.25rem;
	height: 2rem;
	justify-content: center;
}

.node-automation__node-text {
	display: grid;
	min-width: 0;
}

.node-automation__node-text strong,
.node-automation__node-text small {
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.node-automation__node-text small {
	color: #d6d6d6;
	font-size: 0.78rem;
}

.node-automation__inline-edit input {
	background: rgba(0, 0, 0, 0.5);
	border: 1px solid #8b35e6;
	border-radius: 3px;
	color: #fff;
	font-size: 0.78rem;
	outline: none;
	padding: 0 0.2rem;
	width: 100%;
}

.node-automation__node-badge {
	background: #e9aaff;
	border-radius: 4px;
	color: #1b0f21;
	font-size: 0.7rem;
	font-weight: 700;
	padding: 0.2rem 0.35rem;
}

.node-automation__node-run {
	align-items: center;
	background: #4caf50;
	border-radius: 50%;
	color: #fff;
	cursor: pointer;
	display: flex;
	font-size: 0.7rem;
	height: 20px;
	justify-content: center;
	width: 20px;
}
.node-automation__node-run:hover {
	background: #66bb6a;
}

.node-automation__test-badge {
	border-radius: 50%;
	font-size: 0.65rem;
	font-weight: 700;
	height: 18px;
	line-height: 18px;
	text-align: center;
	width: 18px;
}

.node-automation__test-badge--ok {
	background: #66bb6a;
	color: #fff;
}

.node-automation__test-badge--error {
	background: #ef5350;
	color: #fff;
}

.node-automation__test-duration {
	background: rgba(79, 195, 247, 0.16);
	border: 1px solid rgba(79, 195, 247, 0.4);
	border-radius: 4px;
	color: #b8eaff;
	font-size: 0.68rem;
	font-weight: 700;
	padding: 0.12rem 0.28rem;
}

.node-automation__node-config {
	border-top: 1px solid rgb(255 255 255 / 0.1);
	display: grid;
	gap: 0;
	grid-column: 1 / -1;
	margin: 0;
	padding-top: 0.3rem;
}

.node-automation__node-config-line {
	display: flex;
	gap: 0.35rem;
	line-height: 1.25;
}

.node-automation__node-config-line dt {
	color: #b0b0b0;
	flex-shrink: 0;
	font-size: 0.68rem;
	font-weight: 600;
	max-width: 5.5rem;
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.node-automation__node-config-line dd {
	color: #e9e9e9;
	flex: 1;
	font-size: 0.68rem;
	margin: 0;
	min-width: 0;
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.node-automation__node-ports {
	border-top: 1px solid rgb(255 255 255 / 0.1);
	grid-column: 1 / -1;
	padding-top: 0.25rem;
}

.node-automation__port-columns {
	display: flex;
	gap: 0.5rem;
	justify-content: space-between;
}

.node-automation__port-list {
	display: grid;
	gap: 0;
	list-style: none;
	margin: 0;
	padding: 0;
}

.node-automation__port-list--in {
	align-items: flex-start;
}

.node-automation__port-list--out {
	align-items: flex-end;
	margin-left: auto;
}

.node-automation__port {
	align-items: center;
	display: flex;
	gap: 0.25rem;
	line-height: 1.15;
}

.node-automation__port--out {
	justify-content: flex-end;
}

.node-automation__port-dot {
	border: 2px solid #7d32d4;
	border-radius: 50%;
	cursor: crosshair;
	flex-shrink: 0;
	height: 10px;
	position: relative;
	transition: transform 0.12s, box-shadow 0.12s;
	width: 10px;
}

.node-automation__port-dot::before {
	content: "";
	inset: -6px;
	position: absolute;
}

.node-automation__port-dot:hover {
	box-shadow: 0 0 6px 2px currentColor;
	transform: scale(1.4);
}

.node-automation__port-dot.drag-valid {
	box-shadow: 0 0 0 4px rgb(46 212 122 / 0.3), 0 0 10px rgb(46 212 122 / 0.55);
	transform: scale(1.5);
}

.node-automation__port-dot.drag-invalid {
	background: #ef5350 !important;
	border-color: #ffb3b3 !important;
	box-shadow: 0 0 0 4px rgb(239 83 80 / 0.28), 0 0 12px rgb(239 83 80 / 0.65);
	transform: scale(1.55);
}

.node-automation__port-dot--in {
	border-color: #4a8a4d;
}

.node-automation__port-dot--out {
	border-color: #2980b9;
}

.node-automation__port-dot--exec {
	border-color: #e9aaff;
	background: #e9aaff44;
}

.node-automation__port-dot--exec.connected {
	background: #e9aaff;
}

.node-automation__port-dot--exec:hover {
	box-shadow: 0 0 6px 2px #e9aaff;
}

.node-automation__port-label {
	color: #d6d6d6;
	font-size: 0.65rem;
	max-width: 5rem;
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.node-automation__port-type {
	color: rgb(255 255 255 / 0.35);
	font-family: monospace;
	font-size: 0.58rem;
}

.node-automation__resize-handle {
	border-bottom: 2px solid rgb(233 170 255 / 0.48);
	border-right: 2px solid rgb(233 170 255 / 0.48);
	bottom: 3px;
	cursor: nwse-resize;
	position: absolute;
	height: 13px;
	right: 3px;
	width: 13px;
	z-index: 10;
}

.node-automation__resize-handle:hover,
.node-automation__resize-handle:active {
	background: rgba(139, 53, 230, 0.4);
	border-radius: 3px;
}
</style>
