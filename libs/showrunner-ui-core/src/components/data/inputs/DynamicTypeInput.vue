<template>
	<data-input
		v-if="dynamicSchema"
		v-model="model"
		:schema="dynamicSchema"
		:no-float="noFloat"
		:local-path="localPath"
		:context="context"
		:secret="secret"
	/>
</template>

<script setup lang="ts">
import { SchemaDynamicType } from "showrunner-schema"
import { SharedDataInputProps } from "../DataInputTypes"
import { onMounted, ref, useModel, watch } from "vue"
import { Schema } from "showrunner-schema"
import DataInput from "../DataInput.vue"

const props = defineProps<
	{
		schema: SchemaDynamicType
		modelValue: any | undefined
	} & SharedDataInputProps
>()

const model = useModel(props, "modelValue")

const dynamicSchema = ref<Schema>()

async function queryDynamicSchema() {
	const response = await props.schema.dynamicType(props.context)
	dynamicSchema.value = response
}

watch(
	() => props.context,
	() => {
		queryDynamicSchema()
	},
	{ deep: true }
)

onMounted(() => queryDynamicSchema())
</script>
