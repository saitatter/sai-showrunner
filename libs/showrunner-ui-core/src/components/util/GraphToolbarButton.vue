<template>
	<button
		type="button"
		:aria-label="ariaLabel || tooltip || label"
		:class="{ active }"
		:disabled="disabled"
		v-tooltip="tooltip || label"
	>
		<i v-if="icon" :class="icon" />
		<slot />
	</button>
</template>

<script setup lang="ts">
defineProps<{
	icon?: string
	label: string
	tooltip?: string
	ariaLabel?: string
	active?: boolean
	disabled?: boolean
}>()
</script>
