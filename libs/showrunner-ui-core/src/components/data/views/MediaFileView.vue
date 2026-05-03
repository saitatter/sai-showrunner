<template>
	<span class="data-label" v-if="schema.name && !noLabel">{{ schema.name }}:</span> {{ modelValue }}
</template>

<script setup lang="ts">
import { SchemaMediaFile } from "showrunner-schema"
import { MediaFile } from "showrunner-schema"
import { SharedDataViewProps } from "../DataInputTypes"

const props = defineProps<
	{
		modelValue: MediaFile
		schema: SchemaMediaFile
	} & SharedDataViewProps
>()
</script>
