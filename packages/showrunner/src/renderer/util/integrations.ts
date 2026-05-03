import { computed, markRaw } from "vue"
import { ProjectGroup, ProjectItem, usePluginStore, useProjectStore } from "showrunner-ui-core"
import PluginVisibilityToggle from "../components/integrations/PluginVisibilityToggle.vue"

export function initializeIntegrationVisibility() {
	const pluginStore = usePluginStore()
	const projectStore = useProjectStore()

	projectStore.registerProjectGroupChild(
		{
			id: "integrations",
			title: "Integrations",
			icon: "mdi mdi-connection",
		},
		computed<ProjectGroup>(() => ({
			id: "plugin-visibility",
			title: "Plugin Visibility",
			icon: "mdi mdi-puzzle-outline",
			items: [...pluginStore.pluginMap.values()]
				.map<ProjectItem>((plugin) => ({
					id: plugin.id,
					title: plugin.name,
					icon: plugin.icon,
					endComponent: markRaw(PluginVisibilityToggle),
				}))
				.sort((a, b) => a.title.localeCompare(b.title)),
		}))
	)
}
