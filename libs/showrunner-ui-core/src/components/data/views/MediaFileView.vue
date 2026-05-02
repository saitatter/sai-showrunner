<template>
	<span class="data-label" v-if="schema.name && !noLabel">{{ schema.name }}:</span> {{ modelValue }}
</template>

<script setup lang="ts">
import { SchemaMediaFile } from "ShowRunner-schema"
import { MediaFile } from "ShowRunner-schema"
import { SharedDataViewProps } from "../DataInputTypes"

const props = defineProps<
	{
		modelValue: MediaFile
		schema: SchemaMediaFile
	} & SharedDataViewProps
>()
</script>
