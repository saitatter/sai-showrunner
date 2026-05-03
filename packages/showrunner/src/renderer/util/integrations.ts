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
			items: buildPluginCategoryGroups([...pluginStore.pluginMap.values()].map((plugin) => ({
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
			}))),
		}))
	)
}

const PLUGIN_CATEGORIES = [
	{
		id: "streaming-chat",
		title: "Streaming & Chat",
		icon: "mdi mdi-message-video",
		plugins: new Set(["twitch", "youtube", "discord", "bluesky", "moderation", "stream-plans", "spellcast"]),
	},
	{
		id: "production-overlays",
		title: "Production & Overlays",
		icon: "mdi mdi-layers-triple-outline",
		plugins: new Set(["obs", "overlays", "sound", "dashboards", "advss", "aitum", "voicemod"]),
	},
	{
		id: "devices-lights",
		title: "Devices & Lights",
		icon: "mdi mdi-lightbulb-group-outline",
		plugins: new Set(["elgato", "govee", "iot", "lifx", "minecraft", "philips-hue", "tplink-kasa", "twinkly", "wyze", "input"]),
	},
	{
		id: "data-utility",
		title: "Data & Utility",
		icon: "mdi mdi-toolbox-outline",
		plugins: new Set(["ShowRunner", "http", "os", "random", "remote", "time", "variables", "donordrive"]),
	},
]

function buildPluginCategoryGroups(items: ProjectItem[]): ProjectGroup[] {
	const sortedItems = [...items].sort((a, b) => a.title.localeCompare(b.title))
	const byCategory = new Map<string, ProjectItem[]>()

	for (const item of sortedItems) {
		const category = PLUGIN_CATEGORIES.find((candidate) => candidate.plugins.has(item.id))
		const categoryId = category?.id ?? "other"
		const list = byCategory.get(categoryId) ?? []
		list.push(item)
		byCategory.set(categoryId, list)
	}

	const groups = PLUGIN_CATEGORIES.map<ProjectGroup>((category) => ({
		id: `plugins-${category.id}`,
		title: category.title,
		icon: category.icon,
		items: byCategory.get(category.id) ?? [],
	})).filter((group) => group.items.length)

	const other = byCategory.get("other")
	if (other?.length) {
		groups.push({
			id: "plugins-other",
			title: "Other",
			icon: "mdi mdi-puzzle-outline",
			items: other,
		})
	}

	return groups
}
