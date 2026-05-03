<template>
	<boolean-group-expression
		v-if="isBooleanGroup(model)"
		v-model="model"
		:selected-ids="selectedIds"
		@delete="emit('delete', $event)"
	/>
	<boolean-value-expression-editor
		v-else-if="isBooleanValueExpr(model)"
		v-model="model"
		:selected-ids="selectedIds"
		@delete="emit('delete', $event)"
	/>
</template>

<script setup lang="ts">
import { BooleanSubExpression, BooleanValueExpression, BooleanExpressionGroup } from "showrunner-schema"
import BooleanGroupExpression from "./BooleanGroupExpression.vue"
import BooleanValueExpressionEditor from "./BooleanValueExpressionEditor.vue"
import { useModel } from "vue"
import { isBooleanGroup } from "showrunner-schema"
import { isBooleanRangeExpr } from "showrunner-schema"
import { isBooleanValueExpr } from "showrunner-schema"
import { useDataBinding } from "../../../../main"

const props = defineProps<{
	modelValue: BooleanSubExpression
	selectedIds: string[]
	localPath: string
}>()

useDataBinding(() => props.localPath)

const emit = defineEmits(["update:modelValue", "delete"])

const model = useModel(props, "modelValue")
</script>
