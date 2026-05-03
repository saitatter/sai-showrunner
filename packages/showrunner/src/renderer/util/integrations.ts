import { computed, markRaw } from "vue"
import { ProjectGroup, ProjectItem, useDockingStore, usePluginStore, useProjectStore } from "showrunner-ui-core"
import PluginDetailsPage from "../components/integrations/PluginDetailsPage.vue"
import PluginVisibilityToggle from "../components/integrations/PluginVisibilityToggle.vue"
import { pluginIcon } from "./plugin-icons"

const NATIVE_INTEGRATION_GROUP_PLUGIN_IDS = new Set(["moderation", "obs", "twitch", "youtube"])

export function initializeIntegrationVisibility() {
	const pluginStore = usePluginStore()
	const projectStore = useProjectStore()
	const dockingStore = useDockingStore()

	const categoryGroups = computed(() => {
		const plugins = [...pluginStore.pluginMap.values()]
			.filter((plugin) => !NATIVE_INTEGRATION_GROUP_PLUGIN_IDS.has(plugin.id))
			.map((plugin) => ({
				id: plugin.id,
				title: plugin.name,
				icon: pluginIcon(plugin.id, plugin.icon),
				iconColor: plugin.color || undefined,
				endComponent: markRaw(PluginVisibilityToggle),
				open() {
					dockingStore.openPage(
						`integration.${plugin.id}`,
						plugin.name,
						pluginIcon(plugin.id, plugin.icon),
						PluginDetailsPage,
						{ pluginId: plugin.id }
					)
				},
			}))
		return buildPluginCategoryGroups(plugins)
	})

	for (const category of PLUGIN_CATEGORIES) {
		projectStore.registerProjectGroupChild(
			{
				id: "integrations",
				title: "Integrations",
				icon: "mdi mdi-connection",
			},
			computed<ProjectGroup>(() => {
				const group = categoryGroups.value.find((g) => g.id === `plugins-${category.id}`)
				return group ?? { id: `plugins-${category.id}`, title: category.title, icon: category.icon, items: [] }
			})
		)
	}

	// "Other" category for uncategorized plugins
	projectStore.registerProjectGroupChild(
		{
			id: "integrations",
			title: "Integrations",
			icon: "mdi mdi-connection",
		},
		computed<ProjectGroup>(() => {
			const group = categoryGroups.value.find((g) => g.id === "plugins-other")
			return group ?? { id: "plugins-other", title: "Other", icon: "mdi mdi-puzzle-outline", items: [] }
		})
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
