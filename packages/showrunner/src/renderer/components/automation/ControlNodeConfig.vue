<template>
	<div class="control-node-config">
		<template v-if="node.type === 'if' || node.type === 'while'">
			<label>
				<span>{{ node.type === 'if' ? 'Condition' : 'Loop while' }}</span>
				<select
					:value="expressionMode(node.condition)"
					@change="setControlExpressionMode(node, 'condition', ($event.target as HTMLSelectElement).value)"
				>
					<option value="true">Always true</option>
					<option value="false">Always false</option>
					<option value="variable">Variable is truthy</option>
					<option value="equals">Variable equals value</option>
				</select>
			</label>
			<label v-if="expressionMode(node.condition) === 'variable' || expressionMode(node.condition) === 'equals'">
				<span>Variable</span>
				<expression-text-input
					list="node-expression-suggestions"
					:model-value="expressionVariable(node.condition)"
					placeholder="message.approved"
					:invalid="Boolean(expressionValidationMessage(node.condition))"
					@change="setControlExpressionVariable(node, 'condition', $event)"
				/>
			</label>
			<label v-if="expressionMode(node.condition) === 'equals'">
				<span>Equals</span>
				<input
					type="text"
					:value="expressionCompareValue(node.condition)"
					placeholder="approved"
					@change="setControlExpressionCompareValue(node, 'condition', ($event.target as HTMLInputElement).value)"
				/>
			</label>
			<div class="control-node-config__expression-summary" :class="{ invalid: Boolean(expressionValidationMessage(node.condition)) }">
				<code>{{ summarizeExpression(node.condition) }}</code>
				<small>{{ expressionValidationMessage(node.condition) || "Expression looks valid" }}</small>
			</div>
			<label v-if="node.type === 'while'">
				<span>Max iterations</span>
				<input
					type="number"
					min="1"
					step="1"
					:value="node.maxIterations ?? 1000"
					@change="setControlNumber(node, 'maxIterations', Number(($event.target as HTMLInputElement).value))"
				/>
			</label>
		</template>
		<template v-else-if="node.type === 'for'">
			<label>
				<span>Counter</span>
				<input
					type="text"
					:value="node.variable"
					@change="setControlString(node, 'variable', ($event.target as HTMLInputElement).value)"
				/>
			</label>
			<label>
				<span>Start</span>
				<input
					type="number"
					:value="literalNumber(node.start)"
					@change="setControlLiteralNumber(node, 'start', Number(($event.target as HTMLInputElement).value))"
				/>
			</label>
			<label>
				<span>End</span>
				<input
					type="number"
					:value="literalNumber(node.end)"
					@change="setControlLiteralNumber(node, 'end', Number(($event.target as HTMLInputElement).value))"
				/>
			</label>
			<label>
				<span>Step</span>
				<input
					type="number"
					:value="literalNumber(node.step, 1)"
					@change="setControlLiteralNumber(node, 'step', Number(($event.target as HTMLInputElement).value))"
				/>
			</label>
		</template>
		<template v-else-if="node.type === 'forEach'">
			<label>
				<span>Item variable</span>
				<input
					type="text"
					:value="node.variable"
					@change="setControlString(node, 'variable', ($event.target as HTMLInputElement).value)"
				/>
			</label>
			<label>
				<span>Collection variable</span>
				<expression-text-input
					list="node-expression-suggestions"
					:model-value="expressionVariable(node.collection)"
					placeholder="items"
					:invalid="Boolean(expressionValidationMessage(node.collection))"
					@change="setControlExpressionVariable(node, 'collection', $event)"
				/>
			</label>
			<div class="control-node-config__expression-summary" :class="{ invalid: Boolean(expressionValidationMessage(node.collection)) }">
				<code>{{ summarizeExpression(node.collection) }}</code>
				<small>{{ expressionValidationMessage(node.collection) || "Expression looks valid" }}</small>
			</div>
		</template>
		<template v-else-if="node.type === 'switch'">
			<label>
				<span>Switch variable</span>
				<expression-text-input
					list="node-expression-suggestions"
					:model-value="expressionVariable(node.expression)"
					placeholder="platform"
					:invalid="Boolean(expressionValidationMessage(node.expression))"
					@change="setControlExpressionVariable(node, 'expression', $event)"
				/>
			</label>
			<div class="control-node-config__expression-summary" :class="{ invalid: Boolean(expressionValidationMessage(node.expression)) }">
				<code>{{ summarizeExpression(node.expression) }}</code>
				<small>{{ expressionValidationMessage(node.expression) || "Expression looks valid" }}</small>
			</div>
			<div class="control-node-config__case-list">
				<div v-for="(item, ci) in node.cases" :key="item.port">
					<input
						type="text"
						:value="String(item.value)"
						placeholder="case value"
						@change="setSwitchCaseValue(node, ci, ($event.target as HTMLInputElement).value)"
					/>
					<button type="button" class="danger" @click="deleteSwitchCase(node, ci)">
						<i class="mdi mdi-trash-can-outline" />
					</button>
				</div>
				<button type="button" @click="addSwitchCase(node)">
					<i class="mdi mdi-plus" /> Add case
				</button>
			</div>
		</template>
		<p v-else class="control-node-config__hint">This control node does not have editable fields yet.</p>
	</div>
</template>

<script setup lang="ts">
import type { Expression, GraphNode } from "showrunner-schema"
import ExpressionTextInput from "./ExpressionTextInput.vue"

defineProps<{
	node: GraphNode
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
}>()
</script>

<style scoped>
.control-node-config {
	display: grid;
	gap: 0.55rem;
}

.control-node-config label {
	display: flex;
	flex-direction: column;
	gap: 0.3rem;
}

.control-node-config label span {
	color: var(--text-color-secondary);
	font-size: 0.75rem;
	font-weight: 600;
	text-transform: uppercase;
}

.control-node-config input,
.control-node-config select {
	background: var(--surface-a);
	border: 1px solid var(--surface-d);
	border-radius: 4px;
	color: var(--text-color);
	font-size: 0.85rem;
	padding: 0.35rem 0.5rem;
}

.control-node-config__case-list {
	display: grid;
	gap: 0.4rem;
}

.control-node-config__case-list > div {
	display: grid;
	gap: 0.35rem;
	grid-template-columns: 1fr auto;
}

.control-node-config__case-list button {
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

.control-node-config__case-list button.danger {
	color: #ffb4b4;
}

.control-node-config__expression-summary {
	background: #101010;
	border: 1px solid #303030;
	border-radius: 5px;
	display: grid;
	gap: 0.25rem;
	padding: 0.5rem;
}

.control-node-config__expression-summary code {
	color: #b8eaff;
	font-family: "Cascadia Code", "Consolas", monospace;
	font-size: 0.78rem;
	overflow-wrap: anywhere;
}

.control-node-config__expression-summary small {
	color: #9fd0a7;
	font-size: 0.72rem;
}

.control-node-config__expression-summary.invalid {
	border-color: rgba(239, 83, 80, 0.55);
}

.control-node-config__expression-summary.invalid small {
	color: #ffb4b4;
}

.control-node-config__hint {
	color: #cfcfcf;
	line-height: 1.45;
	margin: 0;
}
</style>
