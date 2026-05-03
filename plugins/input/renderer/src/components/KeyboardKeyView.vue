<template>
	<span class="data-label" v-if="schema.name && !noLabel">{{ schema.name }}: </span>
	<span v-if="modelValue">
		{{ modelValue }}
	</span>
</template>

<script setup lang="ts">
import { SharedDataViewProps } from "showrunner-ui-core"
import { KeyboardKey, Keys, SchemaKeyboardKey } from "showrunner-plugin-input-shared"
import { computed } from "vue"

const props = defineProps<
	{
		modelValue: KeyboardKey | undefined
		schema: SchemaKeyboardKey
	} & SharedDataViewProps
>()
</script>
