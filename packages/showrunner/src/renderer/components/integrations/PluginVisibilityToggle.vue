<template>
	<span class="plugin-visibility-toggle">
		<toggle-switch
			v-model="enabledModel"
			false-icon="mdi mdi-power-off"
			toggle-icon="mdi mdi-power"
			true-icon="mdi mdi-power"
			:title="enabled ? 'Shown in automation node menus' : 'Hidden from automation node menus'"
		/>
	</span>
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

<style scoped>
.plugin-visibility-toggle {
	align-items: center;
	display: inline-flex;
	flex: 0 0 auto;
	justify-content: center;
	margin-left: auto;
	padding-left: 0.25rem;
}

.plugin-visibility-toggle :deep(.toggler) {
	box-shadow: inset 0 0 0 1px rgb(255 255 255 / 0.18);
	transform: scale(0.78);
	transform-origin: center center;
	vertical-align: middle;
}

.plugin-visibility-toggle :deep(.toggler.toggle-true) {
	background: #15803d;
}

.plugin-visibility-toggle :deep(.toggler.toggle-false) {
	background: #991b1b;
}

.plugin-visibility-toggle :deep(.toggle-ball) {
	background-color: #f2f2f2;
}
</style>
