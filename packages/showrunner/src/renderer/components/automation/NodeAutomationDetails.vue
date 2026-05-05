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
						/>
						<div v-else-if="selectedActionMissing" class="node-automation__missing-schema">
							<i class="mdi mdi-alert-circle-outline" />
							<strong>Missing action schema</strong>
							<span>{{ selectedActionInfo?.plugin }} / {{ selectedActionInfo?.action }}</span>
							<small>The plugin or action was removed or renamed. The node is preserved so you can reconnect it or delete it safely.</small>
						</div>
						<div v-else-if="selectedTriggerMissing" class="node-automation__missing-schema">
							<i class="mdi mdi-alert-circle-outline" />
							<strong>Missing trigger schema</strong>
							<span>{{ selectedTriggerConfigModel?.plugin }} / {{ selectedTriggerConfigModel?.trigger }}</span>
							<small>The trigger was removed or renamed. Pick a new trigger from the context menu to repair this automation.</small>
						</div>
						<trigger-config-edit v-else-if="selectedNode.kind === 'trigger' && selectedTriggerConfigModel" v-model="selectedTriggerConfigModelModel" />
						<div v-else-if="selectedNode.kind === 'variable' && selectedVariableNode" class="node-automation__variable-edit">
							<label>
								<span>Name</span>
								<input
									type="text"
									:value="selectedVariableNode?.name"
									placeholder="Variable name..."
									@change="onUpdateVariableNodeName(($event.target as HTMLInputElement).value)"
								/>
							</label>
							<label>
								<span>Value</span>
								<input
									v-if="selectedVariableNode?.type === 'string'"
									type="text"
									:value="selectedVariableNode.value"
									@change="onUpdateVariableNodeValue(($event.target as HTMLInputElement).value)"
								/>
								<input
									v-else-if="selectedVariableNode?.type === 'number'"
									type="number"
									:value="selectedVariableNode.value"
									step="any"
									@change="onUpdateVariableNodeValue(Number(($event.target as HTMLInputElement).value))"
								/>
								<select
									v-else-if="selectedVariableNode?.type === 'boolean'"
									:value="String(selectedVariableNode.value)"
									@change="onUpdateVariableNodeValue(($event.target as HTMLSelectElement).value === 'true')"
								>
									<option value="true">true</option>
									<option value="false">false</option>
								</select>
								<input
									v-else-if="selectedVariableNode?.type === 'color'"
									type="color"
									:value="selectedVariableNode.value"
									@change="onUpdateVariableNodeValue(($event.target as HTMLInputElement).value)"
								/>
							</label>
						</div>
						<div v-else-if="selectedControlNode" class="node-automation__control-edit">
							<template v-if="selectedControlNode.type === 'if' || selectedControlNode.type === 'while'">
								<label>
									<span>{{ selectedControlNode.type === 'if' ? 'Condition' : 'Loop while' }}</span>
									<select
										:value="expressionMode(selectedControlNode.condition)"
										@change="setControlExpressionMode(selectedControlNode, 'condition', ($event.target as HTMLSelectElement).value)"
									>
										<option value="true">Always true</option>
										<option value="false">Always false</option>
										<option value="variable">Variable is truthy</option>
										<option value="equals">Variable equals value</option>
									</select>
								</label>
								<label v-if="expressionMode(selectedControlNode.condition) === 'variable' || expressionMode(selectedControlNode.condition) === 'equals'">
									<span>Variable</span>
									<expression-text-input
										list="node-expression-suggestions"
										:model-value="expressionVariable(selectedControlNode.condition)"
										placeholder="message.approved"
										:invalid="Boolean(expressionValidationMessage(selectedControlNode.condition))"
										@change="setControlExpressionVariable(selectedControlNode, 'condition', $event)"
									/>
								</label>
								<label v-if="expressionMode(selectedControlNode.condition) === 'equals'">
									<span>Equals</span>
									<input
										type="text"
										:value="expressionCompareValue(selectedControlNode.condition)"
										placeholder="approved"
										@change="setControlExpressionCompareValue(selectedControlNode, 'condition', ($event.target as HTMLInputElement).value)"
									/>
								</label>
								<div class="node-automation__expression-summary" :class="{ invalid: Boolean(expressionValidationMessage(selectedControlNode.condition)) }">
									<code>{{ summarizeExpression(selectedControlNode.condition) }}</code>
									<small>{{ expressionValidationMessage(selectedControlNode.condition) || "Expression looks valid" }}</small>
								</div>
								<label v-if="selectedControlNode.type === 'while'">
									<span>Max iterations</span>
									<input
										type="number"
										min="1"
										step="1"
										:value="selectedControlNode.maxIterations ?? 1000"
										@change="setControlNumber(selectedControlNode, 'maxIterations', Number(($event.target as HTMLInputElement).value))"
									/>
								</label>
							</template>
							<template v-else-if="selectedControlNode.type === 'for'">
								<label>
									<span>Counter</span>
									<input
										type="text"
										:value="selectedControlNode.variable"
										@change="setControlString(selectedControlNode, 'variable', ($event.target as HTMLInputElement).value)"
									/>
								</label>
								<label>
									<span>Start</span>
									<input
										type="number"
										:value="literalNumber(selectedControlNode.start)"
										@change="setControlLiteralNumber(selectedControlNode, 'start', Number(($event.target as HTMLInputElement).value))"
									/>
								</label>
								<label>
									<span>End</span>
									<input
										type="number"
										:value="literalNumber(selectedControlNode.end)"
										@change="setControlLiteralNumber(selectedControlNode, 'end', Number(($event.target as HTMLInputElement).value))"
									/>
								</label>
								<label>
									<span>Step</span>
									<input
										type="number"
										:value="literalNumber(selectedControlNode.step, 1)"
										@change="setControlLiteralNumber(selectedControlNode, 'step', Number(($event.target as HTMLInputElement).value))"
									/>
								</label>
							</template>
							<template v-else-if="selectedControlNode.type === 'forEach'">
								<label>
									<span>Item variable</span>
									<input
										type="text"
										:value="selectedControlNode.variable"
										@change="setControlString(selectedControlNode, 'variable', ($event.target as HTMLInputElement).value)"
									/>
								</label>
								<label>
									<span>Collection variable</span>
									<expression-text-input
										list="node-expression-suggestions"
										:model-value="expressionVariable(selectedControlNode.collection)"
										placeholder="items"
										:invalid="Boolean(expressionValidationMessage(selectedControlNode.collection))"
										@change="setControlExpressionVariable(selectedControlNode, 'collection', $event)"
									/>
								</label>
								<div class="node-automation__expression-summary" :class="{ invalid: Boolean(expressionValidationMessage(selectedControlNode.collection)) }">
									<code>{{ summarizeExpression(selectedControlNode.collection) }}</code>
									<small>{{ expressionValidationMessage(selectedControlNode.collection) || "Expression looks valid" }}</small>
								</div>
							</template>
							<template v-else-if="selectedControlNode.type === 'switch'">
								<label>
									<span>Switch variable</span>
									<expression-text-input
										list="node-expression-suggestions"
										:model-value="expressionVariable(selectedControlNode.expression)"
										placeholder="platform"
										:invalid="Boolean(expressionValidationMessage(selectedControlNode.expression))"
										@change="setControlExpressionVariable(selectedControlNode, 'expression', $event)"
									/>
								</label>
								<div class="node-automation__expression-summary" :class="{ invalid: Boolean(expressionValidationMessage(selectedControlNode.expression)) }">
									<code>{{ summarizeExpression(selectedControlNode.expression) }}</code>
									<small>{{ expressionValidationMessage(selectedControlNode.expression) || "Expression looks valid" }}</small>
								</div>
								<div class="node-automation__case-list">
									<div v-for="(item, ci) in selectedControlNode.cases" :key="item.port">
										<input
											type="text"
											:value="String(item.value)"
											placeholder="case value"
											@change="setSwitchCaseValue(selectedControlNode, ci, ($event.target as HTMLInputElement).value)"
										/>
										<button type="button" class="danger" @click="deleteSwitchCase(selectedControlNode, ci)">
											<i class="mdi mdi-trash-can-outline" />
										</button>
									</div>
									<button type="button" @click="addSwitchCase(selectedControlNode)">
										<i class="mdi mdi-plus" /> Add case
									</button>
								</div>
							</template>
							<p v-else class="node-automation__hint">This control node does not have editable fields yet.</p>
						</div>
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
				<div v-if="actionsOpenModel" class="node-automation__quick-actions">
					<div class="node-automation__action-picker">
						<label>
							<span>Add Action</span>
							<input v-model="actionPaletteQueryModel" type="search" placeholder="Search plugin or action..." />
							<select v-model="selectedActionToAddModel">
								<option value="">Choose an action...</option>
								<optgroup v-for="plugin in actionPalette" :key="plugin.id" :label="plugin.name">
									<option v-for="action in plugin.actions" :key="action.key" :value="action.key">
										{{ action.name }}
									</option>
								</optgroup>
							</select>
						</label>
						<button type="button" :disabled="!selectedActionToAdd" @click="onAddActionFromPalette()">
							<i class="mdi mdi-plus" />
							Insert After Selection
						</button>
						<div class="node-automation__palette-list">
							<button
								v-for="action in flatActionPalette"
								:key="action.key"
								type="button"
								draggable="true"
								@click="selectedActionToAddModel = action.key"
								@dragstart="onStartActionPaletteDrag($event, action.key)"
							>
								<i class="mdi mdi-drag" />
								<span>{{ action.pluginName }}</span>
								<strong>{{ action.name }}</strong>
							</button>
						</div>
					</div>
					<div class="node-automation__action-grid">
						<button type="button" :disabled="!canEditSelectedAction" @click="onDuplicateSelectedAction()">
							<i class="mdi mdi-content-duplicate" />
							Duplicate
						</button>
						<button type="button" :disabled="!canMoveSelectedAction(-1)" @click="onMoveSelectedAction(-1)">
							<i class="mdi mdi-arrow-left" />
							Move Left
						</button>
						<button type="button" :disabled="!canMoveSelectedAction(1)" @click="onMoveSelectedAction(1)">
							<i class="mdi mdi-arrow-right" />
							Move Right
						</button>
						<button type="button" class="danger" :disabled="!canEditSelectedAction" @click="onDeleteSelectedAction()">
							<i class="mdi mdi-trash-can-outline" />
							Delete
						</button>
					</div>
					<button type="button" @click="onResetSelectedNodePosition()">
						<i class="mdi mdi-crosshairs-gps" />
						Reset Visual Position
					</button>
					<button type="button" :disabled="selectedNodeIds.size < 1" @click="onCollapseSelectionToSubgraph()">
						<i class="mdi mdi-function" />
						Collapse Selection to Subgraph
					</button>
				</div>
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
			<div v-if="subgraphsOpenModel" class="node-automation__subgraphs">
				<ul v-if="subgraphsList.length" class="node-automation__subgraph-list">
					<li
						v-for="sg in subgraphsList"
						:key="sg.id"
						class="node-automation__subgraph-item"
						:class="{ focused: focusedSubgraphId === sg.id }"
					>
						<label class="node-automation__subgraph-name">
							<i class="mdi mdi-function" />
							<input
								type="text"
								:value="sg.name"
								placeholder="Subgraph name"
								@change="onUpdateSubgraphName(sg.id, ($event.target as HTMLInputElement).value)"
							/>
						</label>
						<span class="node-automation__subgraph-meta">
							{{ sg.parameters.length }} param{{ sg.parameters.length === 1 ? '' : 's' }},
							{{ sg.outputs.length }} output{{ sg.outputs.length === 1 ? '' : 's' }},
							{{ sg.nodes.length }} node{{ sg.nodes.length === 1 ? '' : 's' }}
						</span>
						<div class="node-automation__subgraph-tools">
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
						<div class="node-automation__subgraph-params">
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
						<button type="button" class="danger" title="Delete subgraph" @click="onDeleteSubgraph(sg.id)">
							<i class="mdi mdi-trash-can-outline" />
						</button>
					</li>
				</ul>
				<p v-else class="node-automation__hint">No subgraphs defined.</p>
				<button type="button" class="node-automation__add-subgraph" @click="onAddSubgraph()">
					<i class="mdi mdi-plus" /> New Subgraph
				</button>
			</div>
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
import ExpressionTextInput from "./ExpressionTextInput.vue"

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

.node-automation__missing-schema {
	align-items: start;
	background: rgba(239, 83, 80, 0.1);
	border: 1px solid rgba(239, 83, 80, 0.35);
	border-radius: 5px;
	color: #ffd8d8;
	display: grid;
	gap: 0.35rem;
	padding: 0.75rem;
}

.node-automation__missing-schema i {
	color: #ff7777;
	font-size: 1.4rem;
}

.node-automation__missing-schema span,
.node-automation__missing-schema small {
	color: #ffbcbc;
}

.node-automation__quick-actions {
	display: grid;
	gap: 0.5rem;
	padding: 0.65rem;
}

.node-automation__action-picker {
	display: grid;
	gap: 0.5rem;
}

.node-automation__action-picker label {
	display: grid;
	gap: 0.3rem;
}

.node-automation__action-picker span {
	color: #d9d9d9;
	font-size: 0.78rem;
}

.node-automation__action-picker input,
.node-automation__action-picker select {
	background: #0e0e0e;
	border: 1px solid #4d4d4d;
	border-radius: 4px;
	color: var(--text-color);
	min-width: 0;
	padding: 0.55rem;
}

.node-automation__action-grid {
	display: grid;
	gap: 0.5rem;
	grid-template-columns: 1fr 1fr;
}

.node-automation__palette-list {
	display: grid;
	gap: 0.35rem;
	max-height: 13rem;
	overflow: auto;
	padding-right: 0.15rem;
}

.node-automation__palette-list button {
	align-items: center;
	background: #151515;
	border: 1px solid #3d3d3d;
	border-radius: 4px;
	color: var(--text-color);
	cursor: grab;
	display: grid;
	gap: 0.4rem;
	grid-template-columns: 1.25rem minmax(4rem, 0.7fr) minmax(0, 1fr);
	padding: 0.45rem 0.5rem;
	text-align: left;
}

.node-automation__palette-list button:active {
	cursor: grabbing;
}

.node-automation__palette-list span,
.node-automation__palette-list strong {
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.node-automation__palette-list span {
	color: #bbb;
}

.node-automation__quick-actions button {
	align-items: center;
	background: #2b173d;
	border: 1px solid #7041a6;
	border-radius: 4px;
	color: var(--text-color);
	cursor: pointer;
	display: flex;
	gap: 0.45rem;
	padding: 0.65rem 0.75rem;
	text-align: left;
}

.node-automation__quick-actions button.danger {
	background: #3a171b;
	border-color: #8f3744;
}

.node-automation__quick-actions button:disabled {
	cursor: not-allowed;
	opacity: 0.45;
}

.node-automation__details dl {
	display: grid;
	gap: 0.75rem;
	margin: 0;
	padding: 0.75rem;
}

.node-automation__subgraphs {
	padding: 0.65rem;
}

.node-automation__subgraph-list {
	display: grid;
	gap: 0.4rem;
	list-style: none;
	margin: 0 0 0.5rem;
	padding: 0;
}

.node-automation__subgraph-item {
	align-items: center;
	background: #101010;
	border: 1px solid #303030;
	border-radius: 4px;
	display: grid;
	gap: 0.2rem;
	grid-template-columns: 1fr auto;
	padding: 0.5rem 0.6rem;
}

.node-automation__subgraph-item.focused {
	border-color: #e9aaff;
	box-shadow: 0 0 0 1px rgba(233, 170, 255, 0.25);
}

.node-automation__subgraph-name {
	align-items: center;
	display: flex;
	gap: 0.45rem;
	font-weight: 500;
}

.node-automation__subgraph-name input,
.node-automation__subgraph-params input,
.node-automation__subgraph-params select {
	background: #070707;
	border: 1px solid #333;
	border-radius: 4px;
	color: #eee;
	min-width: 0;
	padding: 0.35rem 0.45rem;
}

.node-automation__subgraph-name input {
	width: 100%;
}

.node-automation__subgraph-meta {
	color: #999;
	font-size: 0.75rem;
	grid-column: 1;
}

.node-automation__subgraph-tools {
	display: flex;
	flex-wrap: wrap;
	gap: 0.35rem;
	grid-column: 1 / -1;
}

.node-automation__subgraph-tools button,
.node-automation__subgraph-params button {
	background: #1e1e1e;
	border: 1px solid #3b3b3b;
	border-radius: 4px;
	color: #ddd;
	cursor: pointer;
	padding: 0.35rem 0.5rem;
}

.node-automation__subgraph-params {
	display: grid;
	gap: 0.35rem;
	grid-column: 1 / -1;
	margin-top: 0.35rem;
}

.node-automation__subgraph-params > div {
	display: grid;
	gap: 0.35rem;
	grid-template-columns: minmax(0, 1fr) 6.5rem minmax(0, 1fr) auto;
}

.node-automation__subgraph-params strong {
	color: #ddd;
	font-size: 0.75rem;
	margin-top: 0.25rem;
	text-transform: uppercase;
}

.node-automation__subgraph-item > .danger {
	background: transparent;
	border: none;
	color: #ef5350;
	cursor: pointer;
	grid-row: 1 / 3;
	grid-column: 2;
	padding: 0.3rem;
}

.node-automation__add-subgraph {
	background: #1e1e1e;
	border: 1px dashed #555;
	border-radius: 4px;
	color: #ccc;
	cursor: pointer;
	padding: 0.5rem;
	width: 100%;
}

.node-automation__add-subgraph:hover {
	background: #2a2a2a;
	border-color: #e9aaff;
	color: #fff;
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

.node-automation__annotation-edit,
.node-automation__variable-edit,
.node-automation__control-edit {
	display: grid;
	gap: 0.55rem;
}

.node-automation__annotation-edit label,
.node-automation__variable-edit label,
.node-automation__control-edit label {
	display: flex;
	flex-direction: column;
	gap: 0.3rem;
}

.node-automation__annotation-edit label span,
.node-automation__variable-edit label span,
.node-automation__control-edit label span {
	color: var(--text-color-secondary);
	font-size: 0.75rem;
	font-weight: 600;
	text-transform: uppercase;
}

.node-automation__annotation-edit input,
.node-automation__variable-edit input,
.node-automation__variable-edit select,
.node-automation__control-edit input,
.node-automation__control-edit select {
	background: var(--surface-a);
	border: 1px solid var(--surface-d);
	border-radius: 4px;
	color: var(--text-color);
	font-size: 0.85rem;
	padding: 0.35rem 0.5rem;
}

.node-automation__case-list {
	display: grid;
	gap: 0.4rem;
}

.node-automation__case-list > div {
	display: grid;
	gap: 0.35rem;
	grid-template-columns: 1fr auto;
}

.node-automation__case-list button {
	align-items: center;
	background: #262626;
	border: 1px solid #3a3a3a;
	border-radius: 4px;
	color: var(--text-color);
	cursor: pointer;
	display: inline-flex;
	gap: 0.25rem;
	justify-content: center;
	padding: 0.35rem 0.55rem;
}

.node-automation__case-list button.danger {
	color: #ffb4b4;
}

.node-automation__expression-summary {
	background: #101010;
	border: 1px solid #303030;
	border-radius: 5px;
	display: grid;
	gap: 0.25rem;
	padding: 0.5rem;
}

.node-automation__expression-summary code {
	color: #b8eaff;
	font-family: "Cascadia Code", "Consolas", monospace;
	font-size: 0.78rem;
	overflow-wrap: anywhere;
}

.node-automation__expression-summary small {
	color: #9fd0a7;
	font-size: 0.72rem;
}

.node-automation__expression-summary.invalid {
	border-color: rgba(239, 83, 80, 0.55);
}

.node-automation__expression-summary.invalid small {
	color: #ffb4b4;
}
</style>
