<template>
	<div class="variable-node-config">
		<label>
			<span>Name</span>
			<input
				type="text"
				:value="variableNode.name"
				placeholder="Variable name..."
				@change="$emit('update:name', ($event.target as HTMLInputElement).value)"
			/>
		</label>
		<label>
			<span>Value</span>
			<input
				v-if="variableNode.type === 'string'"
				type="text"
				:value="variableNode.value"
				@change="$emit('update:value', ($event.target as HTMLInputElement).value)"
			/>
			<input
				v-else-if="variableNode.type === 'number'"
				type="number"
				:value="variableNode.value"
				step="any"
				@change="$emit('update:value', Number(($event.target as HTMLInputElement).value))"
			/>
			<select
				v-else-if="variableNode.type === 'boolean'"
				:value="String(variableNode.value)"
				@change="$emit('update:value', ($event.target as HTMLSelectElement).value === 'true')"
			>
				<option value="true">true</option>
				<option value="false">false</option>
			</select>
			<input
				v-else-if="variableNode.type === 'color'"
				type="color"
				:value="String(variableNode.value)"
				@change="$emit('update:value', ($event.target as HTMLInputElement).value)"
			/>
		</label>
	</div>
</template>

<script setup lang="ts">
interface VariableNode {
	id: string
	name: string
	type: string
	value: unknown
}

defineProps<{
	variableNode: VariableNode
}>()

defineEmits<{
	"update:name": [value: string]
	"update:value": [value: unknown]
}>()
</script>

<style scoped>
.variable-node-config {
	display: grid;
	gap: 0.55rem;
}

.variable-node-config label {
	display: flex;
	flex-direction: column;
	gap: 0.3rem;
}

.variable-node-config label span {
	color: var(--text-color-secondary);
	font-size: 0.75rem;
	font-weight: 600;
	text-transform: uppercase;
}

.variable-node-config input,
.variable-node-config select {
	background: var(--surface-a);
	border: 1px solid var(--surface-d);
	border-radius: 4px;
	color: var(--text-color);
	font-size: 0.85rem;
	padding: 0.35rem 0.5rem;
}
</style>
