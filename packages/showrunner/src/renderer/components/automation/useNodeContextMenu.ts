import { computed, ref, type ComputedRef } from "vue"
import type { NodePosition } from "./useNodeCanvas"
import { CORE_CONVERSION_ACTIONS } from "./coreConversionActions"

export interface ContextMenuItem {
	key: string
	pluginId: string
	pluginName: string
	name: string
	icon: string
	color: string
	searchText: string
}

export interface ContextMenuGroup {
	id: string
	name: string
	icon: string
	color: string
	items: ContextMenuItem[]
}

export interface ContextMenuSearchItem extends ContextMenuItem {
	kind: "action" | "trigger"
}

interface ActionCategoryDefinition {
	id: string
	name: string
	icon: string
	color: string
	matches: (item: ContextMenuItem) => boolean
}

interface MenuNode {
	id: string
	title: string
}

interface MenuLane {
	id: string
}

interface MenuAction {
	name: string
	icon?: string
	type?: string
}

interface MenuTrigger {
	name: string
	icon?: string
}

interface MenuPlugin {
	id: string
	name: string
	icon: string
	color?: string
	actions?: Record<string, MenuAction>
	triggers?: Record<string, MenuTrigger>
}

interface PluginStoreLike {
	pluginMap: Map<string, MenuPlugin>
	isPluginEnabled?: (pluginId: string) => boolean
}

export function useNodeContextMenu(
	nodes: ComputedRef<MenuNode[]>,
	pluginStore: PluginStoreLike,
	getCanvasPointFromClient: (clientX: number, clientY: number) => NodePosition,
	getNodeLane: (node: MenuNode) => MenuLane | undefined
) {
	const contextMenu = ref<{ open: boolean; x: number; y: number; nodeId?: string; canvasPoint?: NodePosition }>({
		open: false,
		x: 0,
		y: 0,
	})
	const contextMenuQuery = ref("")
	const contextMenuOpenGroups = ref<Record<string, boolean>>({
		triggers: true,
		actions: true,
		categories: false,
		data: false,
		"category:data-transforms": true,
		"category:queues": true,
		"category:overlays": true,
		"category:obs": true,
		"category:chat": true,
		"category:utility": true,
	})

	const contextMenuSearch = computed(() => contextMenuQuery.value.trim().toLowerCase())
	const contextMenuSubtitle = computed(() => {
		const node = contextMenu.value.nodeId ? nodes.value.find((entry) => entry.id === contextMenu.value.nodeId) : undefined
		if (node) return `Insert after ${node.title} or replace the trigger.`
		return "Add a trigger or drop a new action on the canvas."
	})
	const actionContextGroups = computed(() =>
		buildContextGroups("actions", (plugin) => filterRegularActions(plugin.actions), (entry) => ({
			name: entry.name,
			icon: entry.icon || "mdi mdi-play",
		}))
	)
	const actionCategoryGroups = computed(() =>
		buildActionCategoryGroups(actionContextGroups.value.flatMap((group) => group.items))
	)
	const conversionContextItems = computed(() => {
		const pluginItems = [...pluginStore.pluginMap.values()]
			.filter((plugin) => (pluginStore.isPluginEnabled?.(plugin.id) ?? true) || isBuiltinPlugin(plugin.id))
			.flatMap((plugin) =>
				Object.entries(filterRegularActions(plugin.actions))
					.filter(([id]) => isConversionActionId(id))
					.map(([id, action]) => ({
						key: `${plugin.id}:${id}`,
						pluginId: plugin.id,
						pluginName: plugin.name,
						name: action.name,
						icon: action.icon || "mdi mdi-swap-horizontal",
						color: String(plugin.color || "#e9aaff"),
						searchText: `actions ${plugin.name} ${plugin.id} ${action.name} ${id}`.toLowerCase(),
					}))
			)
		const seen = new Set(pluginItems.map((item) => normalizeActionId(item.key.split(":").slice(1).join(":"))))
		const fallbackItems = CORE_CONVERSION_ACTIONS
			.filter((item) => !seen.has(normalizeActionId(item.id)))
			.map((item) => ({
				key: `ShowRunner:${item.id}`,
				pluginId: "ShowRunner",
				pluginName: "ShowRunner",
				name: item.name,
				icon: item.icon,
				color: "#de84ff",
				searchText: `actions ShowRunner ShowRunner ${item.name} ${item.id}`.toLowerCase(),
			}))

		return [...pluginItems, ...fallbackItems]
			.filter((item) => !contextMenuSearch.value || item.searchText.includes(contextMenuSearch.value))
			.sort((a, b) => a.name.localeCompare(b.name))
	})
	const triggerContextGroups = computed(() =>
		buildContextGroups("triggers", (plugin) => plugin.triggers, (entry) => ({
			name: entry.name,
			icon: entry.icon || "mdi mdi-flash",
		}))
	)
	const contextMenuSearchItems = computed<ContextMenuSearchItem[]>(() => {
		if (!contextMenuSearch.value) return []
		return [
			...triggerContextGroups.value.flatMap((group) => group.items.map((item) => ({ ...item, kind: "trigger" as const }))),
			...actionContextGroups.value.flatMap((group) => group.items.map((item) => ({ ...item, kind: "action" as const }))),
		].sort((a, b) => a.name.localeCompare(b.name))
	})
	const disabledContextMenuSearchItems = computed<ContextMenuSearchItem[]>(() => {
		const query = contextMenuSearch.value
		if (!query) return []
		return [
			...buildSearchItemsForPlugins("triggers", (plugin) => plugin.triggers, (entry) => ({
				name: entry.name,
				icon: entry.icon || "mdi mdi-flash",
			}), false).map((item) => ({ ...item, kind: "trigger" as const })),
			...buildSearchItemsForPlugins("actions", (plugin) => filterRegularActions(plugin.actions), (entry) => ({
				name: entry.name,
				icon: entry.icon || "mdi mdi-play",
			}), false).map((item) => ({ ...item, kind: "action" as const })),
		].sort((a, b) => a.name.localeCompare(b.name))
	})

	function openContextMenu(event: MouseEvent, nodeId?: string) {
		openContextMenuAt(event.clientX, event.clientY, getCanvasPointFromClient(event.clientX, event.clientY), nodeId)
	}

	function openContextMenuAt(clientX: number, clientY: number, canvasPoint?: NodePosition, nodeId?: string) {
		const menuWidth = 340
		const menuHeight = 520
		contextMenu.value = {
			open: true,
			x: Math.max(8, Math.min(clientX, window.innerWidth - menuWidth - 8)),
			y: Math.max(8, Math.min(clientY, window.innerHeight - menuHeight - 8)),
			nodeId,
			canvasPoint,
		}
		contextMenuQuery.value = ""
		contextMenuOpenGroups.value.data = false

		if (nodeId) {
			const node = nodes.value.find((entry) => entry.id === nodeId)
			const lane = node ? getNodeLane(node) : undefined
			if (lane) contextMenuOpenGroups.value[`action:${lane.id}`] = true
		}
	}

	function closeContextMenu() {
		contextMenu.value.open = false
	}

	function toggleContextGroup(key: string) {
		contextMenuOpenGroups.value[key] = !isContextGroupOpen(key)
	}

	function isContextGroupOpen(key: string) {
		return contextMenuOpenGroups.value[key] ?? false
	}

	function buildContextGroups<Entry extends MenuAction | MenuTrigger>(
		kind: "actions" | "triggers",
		getEntries: (plugin: MenuPlugin) => Record<string, Entry> | undefined,
		getMeta: (entry: Entry) => { name: string; icon: string }
	): ContextMenuGroup[] {
		const query = contextMenuSearch.value
		return [...pluginStore.pluginMap.values()]
			.filter((plugin) => pluginStore.isPluginEnabled?.(plugin.id) ?? true)
			.map((plugin) => {
				const items = Object.entries(getEntries(plugin) || {})
					.map(([id, entry]) => {
						const meta = getMeta(entry)
						return {
							key: `${plugin.id}:${id}`,
							pluginId: plugin.id,
							pluginName: plugin.name,
							name: meta.name,
							icon: meta.icon,
							color: String(plugin.color || "#e9aaff"),
							searchText: `${kind} ${plugin.name} ${plugin.id} ${meta.name} ${id}`.toLowerCase(),
						}
					})
					.filter((item) => !query || item.searchText.includes(query))
					.sort((a, b) => a.name.localeCompare(b.name))

				return {
					id: plugin.id,
					name: plugin.name,
					icon: plugin.icon,
					color: String(plugin.color || "#e9aaff"),
					items,
				}
			})
			.filter((group) => group.items.length)
			.sort((a, b) => a.name.localeCompare(b.name))
	}

	function buildSearchItemsForPlugins<Entry extends MenuAction | MenuTrigger>(
		kind: "actions" | "triggers",
		getEntries: (plugin: MenuPlugin) => Record<string, Entry> | undefined,
		getMeta: (entry: Entry) => { name: string; icon: string },
		enabled: boolean
	): ContextMenuItem[] {
		const query = contextMenuSearch.value
		return [...pluginStore.pluginMap.values()]
			.filter((plugin) => (pluginStore.isPluginEnabled?.(plugin.id) ?? true) === enabled)
			.flatMap((plugin) =>
				Object.entries(getEntries(plugin) || {})
					.map(([id, entry]) => {
						const meta = getMeta(entry)
						return {
							key: `${plugin.id}:${id}`,
							pluginId: plugin.id,
							pluginName: plugin.name,
							name: meta.name,
							icon: meta.icon,
							color: String(plugin.color || "#e9aaff"),
							searchText: `${kind} ${plugin.name} ${plugin.id} ${meta.name} ${id}`.toLowerCase(),
						}
					})
					.filter((item) => item.searchText.includes(query))
			)
	}

	function buildActionCategoryGroups(items: ContextMenuItem[]): ContextMenuGroup[] {
		const grouped = new Map<string, ContextMenuItem[]>()
		for (const item of items) {
			const category = ACTION_CATEGORY_DEFINITIONS.find((definition) => definition.matches(item))
			if (!category) continue
			const list = grouped.get(category.id) ?? []
			list.push(item)
			grouped.set(category.id, list)
		}

		return ACTION_CATEGORY_DEFINITIONS
			.map((definition) => ({
				id: definition.id,
				name: definition.name,
				icon: definition.icon,
				color: definition.color,
				items: (grouped.get(definition.id) ?? []).sort((a, b) => a.name.localeCompare(b.name)),
			}))
			.filter((group) => group.items.length)
	}

	function filterRegularActions(actions: Record<string, MenuAction> | undefined) {
		return Object.fromEntries(Object.entries(actions ?? {}).filter(([, action]) => action?.type === "regular"))
	}

	return {
		contextMenu,
		contextMenuQuery,
		contextMenuSubtitle,
		actionContextGroups,
		actionCategoryGroups,
		conversionContextItems,
		triggerContextGroups,
		contextMenuSearchItems,
		disabledContextMenuSearchItems,
		openContextMenu,
		openContextMenuAt,
		closeContextMenu,
		toggleContextGroup,
		isContextGroupOpen,
	}
}

const CONVERSION_ACTION_IDS = new Set(CORE_CONVERSION_ACTIONS.map((action) => normalizeActionId(action.id)))

export function isConversionActionId(actionId: string) {
	return CONVERSION_ACTION_IDS.has(normalizeActionId(actionId))
}

function normalizeActionId(actionId: string) {
	return actionId.replace(/[^a-z0-9]/gi, "").toLowerCase()
}

function isBuiltinPlugin(pluginId: string) {
	return pluginId.toLowerCase() === "showrunner"
}

const ACTION_CATEGORY_DEFINITIONS: ActionCategoryDefinition[] = [
	{
		id: "data-transforms",
		name: "Data Transforms",
		icon: "mdi mdi-swap-horizontal",
		color: "#81c784",
		matches: (item) => {
			const text = categoryText(item)
			return text.includes("convert") || text.includes("parse") || text.includes("json") || text.includes("stringify")
		},
	},
	{
		id: "queues",
		name: "Queues",
		icon: "mdi mdi-tray-full",
		color: "#ffcf5a",
		matches: (item) => categoryText(item).includes("queue"),
	},
	{
		id: "overlays",
		name: "Overlays",
		icon: "mdi mdi-layers-outline",
		color: "#ce93d8",
		matches: (item) => {
			const text = categoryText(item)
			return item.pluginId.toLowerCase() === "overlays" || text.includes("overlay") || text.includes("alert") || text.includes("banner") || text.includes("shader")
		},
	},
	{
		id: "obs",
		name: "OBS",
		icon: "mdi mdi-broadcast",
		color: "#64b5f6",
		matches: (item) => item.pluginId.toLowerCase() === "obs",
	},
	{
		id: "chat",
		name: "Chat",
		icon: "mdi mdi-message-text-outline",
		color: "#4dd0e1",
		matches: (item) => {
			const pluginId = item.pluginId.toLowerCase()
			const text = categoryText(item)
			return ["twitch", "youtube", "discord", "moderation"].includes(pluginId) || text.includes("chat") || text.includes("message") || text.includes("announce") || text.includes("shoutout")
		},
	},
	{
		id: "utility",
		name: "Utility",
		icon: "mdi mdi-toolbox-outline",
		color: "#b0bec5",
		matches: (item) => {
			const pluginId = item.pluginId.toLowerCase()
			return ["http", "os", "random", "time", "variables", "input", "sound", "remote"].includes(pluginId)
		},
	},
]

function categoryText(item: ContextMenuItem) {
	return `${item.pluginId} ${item.pluginName} ${item.key} ${item.name} ${item.searchText}`.toLowerCase()
}
