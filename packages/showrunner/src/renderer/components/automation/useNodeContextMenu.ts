import { computed, ref, type ComputedRef } from "vue"
import type { NodePosition } from "./useNodeCanvas"

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

interface MenuNode {
	id: string
	title: string
}

interface MenuLane {
	id: string
}

interface PluginStoreLike {
	pluginMap: Map<string, any>
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
	const triggerContextGroups = computed(() =>
		buildContextGroups("triggers", (plugin) => plugin.triggers, (entry) => ({
			name: entry.name,
			icon: entry.icon || "mdi mdi-flash",
		}))
	)

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

	function buildContextGroups(
		kind: "actions" | "triggers",
		getEntries: (plugin: any) => Record<string, any>,
		getMeta: (entry: any) => { name: string; icon: string }
	): ContextMenuGroup[] {
		const query = contextMenuSearch.value
		return [...pluginStore.pluginMap.values()]
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

	function filterRegularActions(actions: Record<string, any> | undefined) {
		return Object.fromEntries(Object.entries(actions ?? {}).filter(([, action]) => action?.type === "regular"))
	}

	return {
		contextMenu,
		contextMenuQuery,
		contextMenuSubtitle,
		actionContextGroups,
		triggerContextGroups,
		openContextMenu,
		openContextMenuAt,
		closeContextMenu,
		toggleContextGroup,
		isContextGroupOpen,
	}
}
