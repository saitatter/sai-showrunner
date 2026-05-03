import { computed, markRaw } from "vue"
import { ProjectGroup, ProjectItem, useDockingStore, usePluginStore, useProjectStore } from "showrunner-ui-core"
import PluginDetailsPage from "../components/integrations/PluginDetailsPage.vue"
import PluginVisibilityToggle from "../components/integrations/PluginVisibilityToggle.vue"

export function initializeIntegrationVisibility() {
	const pluginStore = usePluginStore()
	const projectStore = useProjectStore()
	const dockingStore = useDockingStore()

	projectStore.registerProjectGroupChild(
		{
			id: "integrations",
			title: "Integrations",
			icon: "mdi mdi-connection",
		},
		computed<ProjectGroup>(() => ({
			id: "plugins",
			title: "Plugins",
			icon: "mdi mdi-puzzle-outline",
			items: [...pluginStore.pluginMap.values()]
				.map<ProjectItem>((plugin) => ({
					id: plugin.id,
					title: plugin.name,
					icon: plugin.icon,
					endComponent: markRaw(PluginVisibilityToggle),
					open() {
						dockingStore.openPage(
							`integration.${plugin.id}`,
							plugin.name,
							plugin.icon || "mdi mdi-puzzle-outline",
							PluginDetailsPage,
							{ pluginId: plugin.id }
						)
					},
				}))
				.sort((a, b) => a.title.localeCompare(b.title)),
		}))
	)
}
