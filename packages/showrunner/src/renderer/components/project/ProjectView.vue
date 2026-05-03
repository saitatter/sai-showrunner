<template>
	<flex-scroller class="project-view" :class="{ 'project-view--compact': interfacePreferences.preferences.compactProjectSidebar }">
		<project-group-or-item v-for="pi in visibleProjectItems" :key="pi.id" :group-or-item="pi" />
	</flex-scroller>
</template>

<script setup lang="ts">
import { computed } from "vue"
import ProjectGroupOrItem from "./ProjectGroupOrItem.vue"
import { useProjectStore, FlexScroller } from "showrunner-ui-core"
import { useInterfacePreferencesStore } from "../../util/interface-preferences"
import { useProjectSidebarVisibility } from "../../util/project-sidebar-visibility"

const projectStore = useProjectStore()
const interfacePreferences = useInterfacePreferencesStore()
const { isVisible } = useProjectSidebarVisibility()

const visibleProjectItems = computed(() => projectStore.projectItems.filter((projectItem) => isVisible(projectItem)))
</script>

<style scoped>
.project-view {
	width: 300px;
	height: 100%;
	background-color: var(--surface-b);
	flex-shrink: 0;
}

.project-view--compact {
	font-size: 0.88rem;
	width: 250px;
}

.project-view--compact :deep(.project-category-header),
.project-view--compact :deep(.project-item) {
	height: 1.55rem;
}

.project-view--compact :deep(.project-item) {
	padding-right: 0.35rem;
}
</style>
