<template>
	{{ label }}
</template>

<script setup lang="ts">
import { formatDuration } from "showrunner-schema"
import { Duration } from "showrunner-schema"
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
