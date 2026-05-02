<template>
	{{ label }}
</template>

<script setup lang="ts">
import { formatDuration } from "ShowRunner-schema"
import { Duration } from "ShowRunner-schema"
import { computed } from "vue"

const props = withDefaults(
	defineProps<{
		modelValue: Duration | undefined
		decimalPlaces?: number
	}>(),
	{
		decimalPlaces: 3,
	}
)

const label = computed(() => {
	return formatDuration(props.modelValue, props.decimalPlaces)
})
</script>
