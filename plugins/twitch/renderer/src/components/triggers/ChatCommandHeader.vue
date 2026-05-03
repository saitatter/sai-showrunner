<template>
	<b>{{ getCommandInfoString(config.command) }}</b>
</template>

<script setup lang="ts">
import { Command, getCommandInfoString } from "showrunner-schema"

const props = defineProps<{
	config: {
		command: Command
	}
}>()
</script>
