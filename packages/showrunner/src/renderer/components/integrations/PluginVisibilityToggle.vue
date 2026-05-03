<template>
	<button
		type="button"
		class="plugin-visibility-toggle"
		:class="{ enabled }"
		:title="enabled ? 'Shown in automation node menus' : 'Hidden from automation node menus'"
		@click.stop.prevent="toggle"
	>
		<i :class="enabled ? 'mdi mdi-eye-outline' : 'mdi mdi-eye-off-outline'" />
	</button>
</template>

<script setup lang="ts">
import { computed } from "vue"
import { ProjectItem, usePluginStore } from "showrunner-ui-core"

const props = defineProps<{
	item: ProjectItem
}>()

const pluginStore = usePluginStore()
const enabled = computed(() => pluginStore.isPluginEnabled(props.item.id))

function toggle() {
	pluginStore.togglePluginEnabled(props.item.id)
}
</script>

<style scoped>
.plugin-visibility-toggle {
	align-items: center;
	background: rgb(255 255 255 / 0.08);
	border: 1px solid rgb(255 255 255 / 0.16);
	border-radius: 4px;
	color: var(--text-color-secondary);
	cursor: pointer;
	display: flex;
	height: 1.35rem;
	justify-content: center;
	width: 1.8rem;
}

.plugin-visibility-toggle.enabled {
	background: rgb(46 212 122 / 0.14);
	border-color: rgb(46 212 122 / 0.45);
	color: #9df5be;
}
</style>
