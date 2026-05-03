<template>
	<toggle-switch
		v-model="enabledModel"
		false-icon="mdi mdi-eye-off-outline"
		toggle-icon="mdi mdi-eye-outline"
		true-icon="mdi mdi-eye-outline"
		:title="enabled ? 'Shown in automation node menus' : 'Hidden from automation node menus'"
	/>
</template>

<script setup lang="ts">
import { computed } from "vue"
import { ProjectItem, ToggleSwitch, usePluginStore } from "showrunner-ui-core"

const props = defineProps<{
	item: Pick<ProjectItem, "id">
}>()

const pluginStore = usePluginStore()
const enabled = computed(() => pluginStore.isPluginEnabled(props.item.id))
const enabledModel = computed({
	get() {
		return enabled.value
	},
	set(value) {
		pluginStore.setPluginEnabled(props.item.id, value !== false)
	},
})
</script>
