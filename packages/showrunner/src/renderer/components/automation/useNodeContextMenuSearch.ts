import { computed, nextTick, ref, type ComputedRef, type Ref } from "vue"
import type { GraphNodeType, SubgraphDefinition } from "showrunner-schema"

type VariableNodeType = "string" | "number" | "boolean" | "color"
type ControlFlowNodeType = Exclude<GraphNodeType, "action" | "subgraphCall">

export type ContextSearchResult =
	| { kind: "action" | "trigger"; key: string; name: string; detail: string; label: string; icon: string; color: string; searchText: string }
	| { kind: "variable"; key: string; name: string; detail: string; label: string; icon: string; color: string; searchText: string; variableType: VariableNodeType }
	| { kind: "control"; key: string; name: string; detail: string; label: string; icon: string; color: string; searchText: string; controlType: ControlFlowNodeType }
	| { kind: "subgraph"; key: string; name: string; detail: string; label: string; icon: string; color: string; searchText: string; subgraphId: string }

interface ContextMenuSearchItem {
	kind: "action" | "trigger"
	key: string
	name: string
	pluginName: string
	icon: string
	color: string
	searchText: string
}

interface ContextMenuState {
	open: boolean
}

interface UseNodeContextMenuSearchOptions {
	contextMenu: Ref<ContextMenuState>
	contextMenuQuery: Ref<string>
	contextMenuRootRef: Ref<HTMLElement | undefined>
	contextMenuSearchItems: ComputedRef<ContextMenuSearchItem[]>
	disabledContextMenuSearchItems: ComputedRef<ContextMenuSearchItem[]>
	pendingFlowConnection: Ref<unknown>
	subgraphsList: ComputedRef<SubgraphDefinition[]>
	closeContextMenu: () => void
	toggleContextGroup: (id: string) => void
	isContextGroupOpen: (id: string) => boolean
}

const CONTEXT_VARIABLE_ITEMS: Array<Omit<Extract<ContextSearchResult, { kind: "variable" }>, "searchText">> = [
	{ kind: "variable", key: "string", name: "String Variable", detail: "Data", label: "Variable", icon: "mdi mdi-format-text", color: "#81c784", variableType: "string" },
	{ kind: "variable", key: "number", name: "Number Variable", detail: "Data", label: "Variable", icon: "mdi mdi-numeric", color: "#4fc3f7", variableType: "number" },
	{ kind: "variable", key: "boolean", name: "Boolean Variable", detail: "Data", label: "Variable", icon: "mdi mdi-toggle-switch-outline", color: "#ffb74d", variableType: "boolean" },
	{ kind: "variable", key: "color", name: "Color Variable", detail: "Data", label: "Variable", icon: "mdi mdi-palette", color: "#f06292", variableType: "color" },
]

const CONTEXT_CONTROL_ITEMS: Array<Omit<Extract<ContextSearchResult, { kind: "control" }>, "searchText">> = [
	{ kind: "control", key: "if", name: "If / Else", detail: "Conditional branch", label: "Control", icon: "mdi mdi-source-branch", color: "#64b5f6", controlType: "if" },
	{ kind: "control", key: "switch", name: "Switch", detail: "Multi-way branch", label: "Control", icon: "mdi mdi-source-fork", color: "#64b5f6", controlType: "switch" },
	{ kind: "control", key: "for", name: "For Loop", detail: "Counter-based loop", label: "Control", icon: "mdi mdi-repeat", color: "#68d391", controlType: "for" },
	{ kind: "control", key: "forEach", name: "For Each", detail: "Iterate over collection", label: "Control", icon: "mdi mdi-format-list-numbered", color: "#68d391", controlType: "forEach" },
	{ kind: "control", key: "while", name: "While Loop", detail: "Condition-based loop", label: "Control", icon: "mdi mdi-sync", color: "#68d391", controlType: "while" },
	{ kind: "control", key: "break", name: "Break", detail: "Exit current loop", label: "Control", icon: "mdi mdi-debug-step-out", color: "#ef9a9a", controlType: "break" },
	{ kind: "control", key: "continue", name: "Continue", detail: "Next iteration", label: "Control", icon: "mdi mdi-skip-next", color: "#ef9a9a", controlType: "continue" },
	{ kind: "control", key: "return", name: "Return", detail: "End execution", label: "Control", icon: "mdi mdi-keyboard-return", color: "#ef9a9a", controlType: "return" },
]

export function useNodeContextMenuSearch({
	contextMenu,
	contextMenuQuery,
	contextMenuRootRef,
	contextMenuSearchItems,
	disabledContextMenuSearchItems,
	pendingFlowConnection,
	subgraphsList,
	closeContextMenu,
	toggleContextGroup,
	isContextGroupOpen,
}: UseNodeContextMenuSearchOptions) {
	const contextMenuFocusIndex = ref(-1)

	const contextMenuSearchResults = computed<ContextSearchResult[]>(() => {
		const query = contextMenuQuery.value.trim().toLowerCase()
		if (!query) return []

		const integrationItems: ContextSearchResult[] = contextMenuSearchItems.value
			.filter((item) => !pendingFlowConnection.value || item.kind === "action")
			.map((item) => ({
				kind: item.kind,
				key: item.key,
				name: item.name,
				detail: item.pluginName,
				label: item.kind === "trigger" ? "Trigger" : "Action",
				icon: item.icon,
				color: item.color,
				searchText: item.searchText,
			}))
		const variableItems: ContextSearchResult[] = pendingFlowConnection.value
			? []
			: CONTEXT_VARIABLE_ITEMS.map((item) => withContextSearchText(item))
		const controlItems: ContextSearchResult[] = CONTEXT_CONTROL_ITEMS.map((item) => withContextSearchText(item))
		const subgraphItems: ContextSearchResult[] = subgraphsList.value.map((subgraph) => withContextSearchText({
			kind: "subgraph",
			key: subgraph.id,
			name: subgraph.name || "Unnamed",
			detail: "Call subgraph",
			label: "Subgraph",
			icon: "mdi mdi-function",
			color: "#ce93d8",
			subgraphId: subgraph.id,
		}))

		return [...integrationItems, ...variableItems, ...controlItems, ...subgraphItems]
			.filter((item) => item.searchText.includes(query))
			.slice(0, 32)
	})

	const hiddenPluginSearchHint = computed(() => {
		const query = contextMenuQuery.value.trim()
		if (!query || contextMenuSearchResults.value.length) return ""
		const matches = disabledContextMenuSearchItems.value.filter((item) => !pendingFlowConnection.value || item.kind === "action")
		if (!matches.length) return ""
		const pluginNames = [...new Set(matches.map((item) => item.pluginName))].slice(0, 3)
		return `Matches exist in disabled plugins: ${pluginNames.join(", ")}. Turn them on in Integrations to add new nodes.`
	})

	function handleContextMenuKeydown(event: KeyboardEvent) {
		if (!contextMenu.value.open) return
		if (event.key === "Escape") {
			event.preventDefault()
			closeContextMenu()
			return
		}
		if (event.key === "ArrowDown") {
			event.preventDefault()
			moveContextMenuFocus(1)
			return
		}
		if (event.key === "ArrowUp") {
			event.preventDefault()
			moveContextMenuFocus(-1)
			return
		}
		if (event.key === "Enter") {
			event.preventDefault()
			activateContextMenuFocus()
			return
		}
		if ((event.ctrlKey || event.metaKey) && ["1", "2", "3", "4"].includes(event.key)) {
			event.preventDefault()
			openContextMenuSection(event.key)
		}
	}

	function resetContextMenuFocus() {
		contextMenuFocusIndex.value = -1
	}

	function moveContextMenuFocus(delta: number) {
		const buttons = getContextMenuButtons()
		if (!buttons.length) return
		const current = buttons.indexOf(document.activeElement as HTMLButtonElement)
		const start = current >= 0 ? current : contextMenuFocusIndex.value
		const fallback = delta > 0 ? 0 : buttons.length - 1
		const next = start >= 0 ? (start + delta + buttons.length) % buttons.length : fallback
		contextMenuFocusIndex.value = next
		buttons[next].focus({ preventScroll: true })
		buttons[next].scrollIntoView({ block: "nearest" })
	}

	function activateContextMenuFocus() {
		const buttons = getContextMenuButtons()
		if (!buttons.length) return
		const active = buttons.indexOf(document.activeElement as HTMLButtonElement)
		const index = active >= 0 ? active : Math.max(0, contextMenuFocusIndex.value)
		buttons[Math.min(index, buttons.length - 1)].click()
	}

	function openContextMenuSection(shortcut: string) {
		const sectionByShortcut: Record<string, string> = {
			"1": "categories",
			"2": "integrations",
			"3": "data",
			"4": "flow",
		}
		const section = sectionByShortcut[shortcut]
		if (!section) return
		if (!isContextGroupOpen(section)) toggleContextGroup(section)
		nextTick(() => {
			const sectionButton = contextMenuRootRef.value?.querySelector<HTMLButtonElement>(
				`[data-context-section="${section}"]`
			)
			sectionButton?.focus({ preventScroll: true })
		})
	}

	function getContextMenuButtons() {
		return Array.from(
			contextMenuRootRef.value?.querySelectorAll<HTMLButtonElement>(".node-automation__menu-items button") ?? []
		).filter((button) => !button.disabled && button.offsetParent !== null)
	}

	return {
		contextMenuFocusIndex,
		contextMenuSearchResults,
		hiddenPluginSearchHint,
		handleContextMenuKeydown,
		resetContextMenuFocus,
	}
}

function withContextSearchText<T extends Omit<ContextSearchResult, "searchText">>(item: T): T & { searchText: string } {
	return {
		...item,
		searchText: `${item.name} ${item.detail} ${item.label} ${item.key}`.toLowerCase(),
	}
}
