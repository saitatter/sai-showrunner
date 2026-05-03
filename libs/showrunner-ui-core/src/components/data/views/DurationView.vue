<template>
	<span class="data-label" v-if="schema.name && !noLabel">{{ schema.name }}: </span>
	<duration-label :model-value="props.modelValue" />
</template>

<script setup lang="ts">
import { SchemaDuration } from "showrunner-schema"
import { Duration } from "showrunner-schema"
import { SharedDataViewProps } from "../DataInputTypes"
import DurationLabel from "../base-components/DurationLabel.vue"
const props = defineProps<
	{
		modelValue: Duration
		schema: SchemaDuration
	} & SharedDataViewProps
>()
</script>
