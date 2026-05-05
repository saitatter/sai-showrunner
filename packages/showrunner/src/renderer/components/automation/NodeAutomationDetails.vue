<template>
	<aside class="node-automation__details" :class="{ empty: !selectedNode && !selectedAnnotationBlock }">
		<header class="node-automation__details-header">
			<div>
				<p class="node-automation__eyebrow">{{ selectedAnnotationBlock ? "Annotation Block" : selectedNode ? "Node Context" : "Flow Map" }}</p>
				<h3>{{ selectedAnnotationBlock?.label || selectedNode?.title || "Select a node" }}</h3>
			</div>
			<button
				v-if="selectedNode || selectedAnnotationBlock"
				class="node-automation__icon-button"
				type="button"
				aria-label="Close context"
				@click="onClearSelection()"
				v-tooltip="'Close context'"
			>
				<i class="mdi mdi-close" />
			</button>
		</header>

		<template v-if="selectedAnnotationBlock">
			<section class="node-automation__context-section">
				<button type="button" class="node-automation__context-header" :aria-expanded="detailsOpenModel" @click="detailsOpenModel = !detailsOpenModel">
					<span><i class="mdi mdi-vector-rectangle" /> Annotation</span>
					<i :class="detailsOpenModel ? 'mdi mdi-chevron-up' : 'mdi mdi-chevron-down'" />
				</button>
				<div v-if="detailsOpenModel" class="node-automation__annotation-edit">
					<label>
						<span>Label</span>
						<input
							type="text"
							:value="selectedAnnotationBlock.label"
							placeholder="Block label..."
							@change="onUpdateAnnotationBlockLabel(($event.target as HTMLInputElement).value)"
						/>
					</label>
					<label>
						<span>Color</span>
						<input
							type="color"
							:value="selectedAnnotationBlock.color"
							@change="onUpdateAnnotationBlockColor(($event.target as HTMLInputElement).value)"
						/>
					</label>
					<div class="node-automation__annotation-members">
						<span>{{ selectedAnnotationBlockNodeCount }} node{{ selectedAnnotationBlockNodeCount === 1 ? '' : 's' }} in block</span>
						<button type="button" :disabled="selectedNodeCount < 1" @click="onAddSelectionToAnnotationBlock()">
							<i class="mdi mdi-selection-plus" />
							Add Selection
						</button>
						<button type="button" :disabled="selectedAnnotationBlockNodeCount < 1" @click="onClearAnnotationBlockNodes()">
							<i class="mdi mdi-selection-remove" />
							Clear Nodes
						</button>
					</div>
					<button type="button" class="danger" @click="onDeleteAnnotationBlock()">
						<i class="mdi mdi-trash-can-outline" />
						Delete Block
					</button>
				</div>
			</section>
		</template>

		<template v-if="selectedNode">
			<section class="node-automation__context-section">
				<button type="button" class="node-automation__context-header" :aria-expanded="detailsOpenModel" @click="detailsOpenModel = !detailsOpenModel">
					<span><i class="mdi mdi-information-outline" /> Details</span>
					<i :class="detailsOpenModel ? 'mdi mdi-chevron-up' : 'mdi mdi-chevron-down'" />
				</button>
				<dl v-if="detailsOpenModel">
					<div>
						<dt>Type</dt>
						<dd>{{ selectedNode.kind }}</dd>
					</div>
					<div>
						<dt>Source</dt>
						<dd>{{ selectedNode.subtitle }}</dd>
					</div>
					<div v-if="selectedNode.path">
						<dt>Path</dt>
						<dd>{{ selectedNode.path }}</dd>
					</div>
				</dl>
			</section>

			<data-binding-path local-path="automation">
				<section class="node-automation__context-section">
					<button type="button" class="node-automation__context-header" :aria-expanded="configOpenModel" @click="configOpenModel = !configOpenModel">
						<span><i class="mdi mdi-tune" /> Configure</span>
						<i :class="configOpenModel ? 'mdi mdi-chevron-up' : 'mdi mdi-chevron-down'" />
					</button>
					<div v-if="configOpenModel" class="node-automation__config">
						<action-config-edit
							v-if="selectedActionDefModel && !selectedActionMissing"
							v-model="selectedActionDefModel"
							:local-path="selectedActionPath"
							:resolved-action-definition="selectedActionDefinition"
						/>
						<missing-schema-notice
							v-else-if="selectedActionMissing"
							title="Missing action schema"
							:source="`${selectedActionInfo?.plugin} / ${selectedActionInfo?.action}`"
							message="The plugin or action was removed or renamed. The node is preserved so you can reconnect it or delete it safely."
						/>
						<missing-schema-notice
							v-else-if="selectedTriggerMissing"
							title="Missing trigger schema"
							:source="`${selectedTriggerConfigModel?.plugin} / ${selectedTriggerConfigModel?.trigger}`"
							message="The trigger was removed or renamed. Pick a new trigger from the context menu to repair this automation."
						/>
						<trigger-config-edit v-else-if="selectedNode.kind === 'trigger' && selectedTriggerConfigModel" v-model="selectedTriggerConfigModelModel" />
						<variable-node-config
							v-else-if="selectedNode.kind === 'variable' && selectedVariableNode"
							:variable-node="selectedVariableNode"
							@update:name="onUpdateVariableNodeName"
							@update:value="onUpdateVariableNodeValue"
						/>
						<control-node-config
							v-else-if="selectedControlNode"
							:node="selectedControlNode"
							:expression-mode="expressionMode"
							:expression-variable="expressionVariable"
							:expression-compare-value="expressionCompareValue"
							:expression-validation-message="expressionValidationMessage"
							:summarize-expression="summarizeExpression"
							:literal-number="literalNumber"
							:set-control-expression-mode="setControlExpressionMode"
							:set-control-expression-variable="setControlExpressionVariable"
							:set-control-expression-compare-value="setControlExpressionCompareValue"
							:set-control-string="setControlString"
							:set-control-number="setControlNumber"
							:set-control-literal-number="setControlLiteralNumber"
							:set-switch-case-value="setSwitchCaseValue"
							:add-switch-case="addSwitchCase"
							:delete-switch-case="deleteSwitchCase"
						/>
						<p v-else class="node-automation__hint">
							This node groups other actions. Select a child action node to edit its settings.
						</p>
					</div>
				</section>
			</data-binding-path>

			<section class="node-automation__context-section">
				<button type="button" class="node-automation__context-header" :aria-expanded="actionsOpenModel" @click="actionsOpenModel = !actionsOpenModel">
					<span><i class="mdi mdi-dots-horizontal-circle-outline" /> Node Actions</span>
					<i :class="actionsOpenModel ? 'mdi mdi-chevron-up' : 'mdi mdi-chevron-down'" />
				</button>
				<node-action-panel
					v-if="actionsOpenModel"
					v-model:action-palette-query="actionPaletteQueryModel"
					v-model:selected-action-to-add="selectedActionToAddModel"
					:action-palette="actionPalette"
					:flat-action-palette="flatActionPalette"
					:can-edit-selected-action="canEditSelectedAction"
					:selected-node-count="selectedNodeIds.size"
					:on-add-action-from-palette="onAddActionFromPalette"
					:on-start-action-palette-drag="onStartActionPaletteDrag"
					:on-duplicate-selected-action="onDuplicateSelectedAction"
					:on-move-selected-action="onMoveSelectedAction"
					:on-delete-selected-action="onDeleteSelectedAction"
					:on-reset-selected-node-position="onResetSelectedNodePosition"
					:on-collapse-selection-to-subgraph="onCollapseSelectionToSubgraph"
					:can-move-selected-action="canMoveSelectedAction"
				/>
			</section>
		</template>
		<p v-else-if="!selectedAnnotationBlock" class="node-automation__hint">
			Left click selects a node. Right click opens the context menu to add nodes.
		</p>

		<section class="node-automation__context-section">
			<button type="button" class="node-automation__context-header" :aria-expanded="subgraphsOpenModel" @click="subgraphsOpenModel = !subgraphsOpenModel">
				<span><i class="mdi mdi-function-variant" /> Subgraphs</span>
				<i :class="subgraphsOpenModel ? 'mdi mdi-chevron-up' : 'mdi mdi-chevron-down'" />
			</button>
			<subgraph-panel
				v-if="subgraphsOpenModel"
				:subgraphs="subgraphsList"
				:subgraph-param-types="subgraphParamTypes"
				:focused-subgraph-id="focusedSubgraphId"
				:on-add-subgraph="onAddSubgraph"
				:on-focus-subgraph="onFocusSubgraph"
				:on-open-subgraph-canvas="onOpenSubgraphCanvas"
				:on-delete-subgraph="onDeleteSubgraph"
				:on-update-subgraph-name="onUpdateSubgraphName"
				:on-add-subgraph-param="onAddSubgraphParam"
				:on-delete-subgraph-param="onDeleteSubgraphParam"
				:on-update-subgraph-param="onUpdateSubgraphParam"
				:on-add-subgraph-call-node="onAddSubgraphCallNode"
			/>
		</section>

		<section v-if="activeTestExecution?.executionPath?.length" class="node-automation__context-section">
			<div class="node-automation__execution-header">
				<span><i class="mdi mdi-map-marker-path" /> Execution Path</span>
				<small>{{ activeTestExecution.running ? "Running" : "Last run" }}</small>
			</div>
			<ol class="node-automation__execution-path">
				<li v-for="(nodeId, execIdx) in activeTestExecution.executionPath" :key="`${execIdx}:${nodeId}`">
					<span>{{ nodeTitleById(nodeId) }}</span>
					<small v-if="activeTestExecution.nodeErrors[nodeId]" class="error">{{ activeTestExecution.nodeErrors[nodeId] }}</small>
					<small v-else-if="activeTestExecution.nodeDurations[nodeId] != null">{{ formatNodeDuration(activeTestExecution.nodeDurations[nodeId]) }}</small>
					<small v-else>running</small>
				</li>
			</ol>
		</section>
	</aside>
</template>

<script setup lang="ts">
import { computed } from "vue"
import {
	type ActionDefinition,
	ActionConfigEdit,
	DataBindingPath,
	TriggerConfigEdit,
} from "showrunner-ui-core"
import {
	type ActionInfo,
	type AutomationTriggerNode,
	type Expression,
	type GraphNode,
	type SubgraphDefinition,
	type SubgraphParamType,
} from "showrunner-schema"
import type { AnnotationBlock } from "./useAnnotationBlocks"
import type { NodeData } from "./useNodeRendering"
import ControlNodeConfig from "./ControlNodeConfig.vue"
import MissingSchemaNotice from "./MissingSchemaNotice.vue"
import NodeActionPanel from "./NodeActionPanel.vue"
import SubgraphPanel from "./SubgraphPanel.vue"
import VariableNodeConfig from "./VariableNodeConfig.vue"

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

interface ActiveTestExecution {
	running?: boolean
	executionPath?: string[]
	nodeErrors: Record<string, string>
	nodeDurations: Record<string, number>
}

interface VariableNode {
	id: string
	name: string
	type: string
	value: unknown
}

const props = defineProps<{
	selectedNode?: NodeData
	selectedAnnotationBlock?: AnnotationBlock
	selectedActionInfo?: ActionInfo
	selectedActionDef?: ActionInfo
	selectedActionDefinition?: ActionDefinition
	selectedActionPath?: string
	selectedActionMissing: boolean
	selectedTriggerMissing: boolean
	selectedTriggerConfigModel?: AutomationTriggerNode & { testContext?: unknown }
	selectedVariableNode?: VariableNode
	selectedControlNode?: GraphNode
	selectedNodeIds: Set<string>
	detailsOpen: boolean
	configOpen: boolean
	actionsOpen: boolean
	subgraphsOpen: boolean
	actionPaletteQuery: string
	selectedActionToAdd: string
	actionPalette: ActionPalettePlugin[]
	flatActionPalette: FlatActionPaletteItem[]
	canEditSelectedAction: boolean
	focusedSubgraphId?: string
	subgraphsList: SubgraphDefinition[]
	subgraphParamTypes: SubgraphParamType[]
	activeTestExecution?: ActiveTestExecution
	onClearSelection: () => void
	onUpdateAnnotationBlockLabel: (value: string) => void
	onUpdateAnnotationBlockColor: (value: string) => void
	selectedAnnotationBlockNodeCount: number
	selectedNodeCount: number
	onAddSelectionToAnnotationBlock: () => void
	onClearAnnotationBlockNodes: () => void
	onDeleteAnnotationBlock: () => void
	onUpdateVariableNodeName: (value: string) => void
	onUpdateVariableNodeValue: (value: unknown) => void
	expressionMode: (expr: Expression | undefined) => string
	expressionVariable: (expr: Expression | undefined) => string
	expressionCompareValue: (expr: Expression | undefined) => string
	expressionValidationMessage: (expr: Expression | undefined) => string | undefined
	summarizeExpression: (expr: Expression | undefined) => string
	literalNumber: (expr: Expression | undefined, fallback?: number) => number
	setControlExpressionMode: (node: GraphNode, key: string, mode: string) => void
	setControlExpressionVariable: (node: GraphNode, key: string, variable: string) => void
	setControlExpressionCompareValue: (node: GraphNode, key: string, value: string) => void
	setControlString: (node: GraphNode, key: string, value: string) => void
	setControlNumber: (node: GraphNode, key: string, value: number) => void
	setControlLiteralNumber: (node: GraphNode, key: string, value: number) => void
	setSwitchCaseValue: (node: Extract<GraphNode, { type: "switch" }>, index: number, value: string) => void
	addSwitchCase: (node: Extract<GraphNode, { type: "switch" }>) => void
	deleteSwitchCase: (node: Extract<GraphNode, { type: "switch" }>, index: number) => void
	onAddActionFromPalette: () => void
	onStartActionPaletteDrag: (event: DragEvent, actionKey: string) => void
	onDuplicateSelectedAction: () => void
	onMoveSelectedAction: (direction: -1 | 1) => void
	onDeleteSelectedAction: () => void
	onResetSelectedNodePosition: () => void
	onCollapseSelectionToSubgraph: () => void
	canMoveSelectedAction: (direction: -1 | 1) => boolean
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
	nodeTitleById: (nodeId: string) => string
	formatNodeDuration: (durationMs: number) => string
}>()

const emit = defineEmits<{
	"update:detailsOpen": [value: boolean]
	"update:configOpen": [value: boolean]
	"update:actionsOpen": [value: boolean]
	"update:subgraphsOpen": [value: boolean]
	"update:actionPaletteQuery": [value: string]
	"update:selectedActionToAdd": [value: string]
	"update:selectedActionDef": [value: ActionInfo | undefined]
	"update:selectedTriggerConfigModel": [value: (AutomationTriggerNode & { testContext?: unknown }) | undefined]
}>()

const detailsOpenModel = computed({
	get: () => props.detailsOpen,
	set: (value: boolean) => emit("update:detailsOpen", value),
})

const configOpenModel = computed({
	get: () => props.configOpen,
	set: (value: boolean) => emit("update:configOpen", value),
})

const actionsOpenModel = computed({
	get: () => props.actionsOpen,
	set: (value: boolean) => emit("update:actionsOpen", value),
})

const subgraphsOpenModel = computed({
	get: () => props.subgraphsOpen,
	set: (value: boolean) => emit("update:subgraphsOpen", value),
})

const actionPaletteQueryModel = computed({
	get: () => props.actionPaletteQuery,
	set: (value: string) => emit("update:actionPaletteQuery", value),
})

const selectedActionToAddModel = computed({
	get: () => props.selectedActionToAdd,
	set: (value: string) => emit("update:selectedActionToAdd", value),
})

const selectedActionDefModel = computed({
	get: () => props.selectedActionDef,
	set: (value: ActionInfo | undefined) => emit("update:selectedActionDef", value),
})

const selectedTriggerConfigModelModel = computed({
	get: () => props.selectedTriggerConfigModel,
	set: (value: (AutomationTriggerNode & { testContext?: unknown }) | undefined) => emit("update:selectedTriggerConfigModel", value),
})
</script>

<style scoped>
.node-automation__details h3 {
	margin: 0;
}

.node-automation__eyebrow {
	color: #e9aaff;
	font-size: 0.72rem;
	font-weight: 700;
	letter-spacing: 0;
	margin: 0 0 0.2rem;
	text-transform: uppercase;
}

.node-automation__details {
	background: #111;
	border-left: 1px solid #343434;
	display: flex;
	flex-direction: column;
	gap: 0.85rem;
	padding: 1rem;
}

.node-automation__details.empty {
	justify-content: flex-start;
}

.node-automation__details-header {
	align-items: flex-start;
	display: flex;
	gap: 0.75rem;
	justify-content: space-between;
}

.node-automation__icon-button {
	align-items: center;
	background: #2c2c2c;
	border: 1px solid #454545;
	border-radius: 4px;
	color: var(--text-color);
	cursor: pointer;
	display: flex;
	height: 2rem;
	justify-content: center;
	width: 2rem;
}

.node-automation__context-section {
	background: #181818;
	border: 1px solid #303030;
	border-radius: 6px;
	overflow: hidden;
}

.node-automation__context-header {
	align-items: center;
	background: #222;
	border: 0;
	color: var(--text-color);
	cursor: pointer;
	display: flex;
	font-weight: 700;
	justify-content: space-between;
	padding: 0.7rem 0.8rem;
	width: 100%;
}

.node-automation__context-header span {
	align-items: center;
	display: flex;
	gap: 0.45rem;
}

.node-automation__config {
	max-height: 52vh;
	overflow: auto;
	padding: 0.55rem;
}

.node-automation__details dl {
	display: grid;
	gap: 0.75rem;
	margin: 0;
	padding: 0.75rem;
}

.node-automation__execution-header {
	align-items: center;
	background: #222;
	color: var(--text-color);
	display: flex;
	font-weight: 700;
	justify-content: space-between;
	padding: 0.7rem 0.8rem;
}

.node-automation__execution-header span {
	align-items: center;
	display: flex;
	gap: 0.45rem;
}

.node-automation__execution-header small {
	color: #b8eaff;
	font-size: 0.72rem;
	text-transform: uppercase;
}

.node-automation__execution-path {
	counter-reset: execution-step;
	display: grid;
	gap: 0.4rem;
	list-style: none;
	margin: 0;
	max-height: 13rem;
	overflow: auto;
	padding: 0.65rem;
}

.node-automation__execution-path li {
	align-items: center;
	background: #101010;
	border: 1px solid #303030;
	border-radius: 4px;
	counter-increment: execution-step;
	display: grid;
	gap: 0.15rem;
	grid-template-columns: 1fr auto;
	padding: 0.5rem 0.6rem;
}

.node-automation__execution-path li::before {
	color: #e9aaff;
	content: counter(execution-step, decimal-leading-zero);
	font-size: 0.68rem;
	font-weight: 800;
	grid-column: 1 / -1;
	letter-spacing: 0.04em;
}

.node-automation__execution-path span {
	font-weight: 700;
	min-width: 0;
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.node-automation__execution-path small {
	color: #b8eaff;
	font-size: 0.72rem;
}

.node-automation__execution-path small.error {
	color: #ffb4b4;
	max-width: 12rem;
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.node-automation__details dl div {
	display: grid;
	gap: 0.2rem;
}

.node-automation__details dt {
	color: #aaa;
	font-size: 0.78rem;
}

.node-automation__details dd {
	margin: 0;
	overflow-wrap: anywhere;
}

.node-automation__hint {
	color: #cfcfcf;
	line-height: 1.45;
	margin: 0;
}

.node-automation__annotation-edit {
	display: grid;
	gap: 0.55rem;
}

.node-automation__annotation-edit label {
	display: flex;
	flex-direction: column;
	gap: 0.3rem;
}

.node-automation__annotation-edit label span {
	color: var(--text-color-secondary);
	font-size: 0.75rem;
	font-weight: 600;
	text-transform: uppercase;
}

.node-automation__annotation-edit input {
	background: var(--surface-a);
	border: 1px solid var(--surface-d);
	border-radius: 4px;
	color: var(--text-color);
	font-size: 0.85rem;
	padding: 0.35rem 0.5rem;
}

.node-automation__annotation-members {
	background: #101010;
	border: 1px solid #303030;
	border-radius: 5px;
	display: grid;
	gap: 0.45rem;
	padding: 0.55rem;
}

.node-automation__annotation-members span {
	color: #d6d6d6;
	font-size: 0.78rem;
}

.node-automation__annotation-members button,
.node-automation__annotation-edit > button {
	align-items: center;
	background: #2b173d;
	border: 1px solid #7041a6;
	border-radius: 4px;
	color: var(--text-color);
	cursor: pointer;
	display: inline-flex;
	gap: 0.4rem;
	justify-content: center;
	padding: 0.45rem 0.6rem;
}

.node-automation__annotation-edit > button.danger {
	background: #3a171b;
	border-color: #8f3744;
}

.node-automation__annotation-members button:disabled {
	cursor: not-allowed;
	opacity: 0.45;
}
</style>
