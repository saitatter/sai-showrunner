import { computed, type Ref } from "vue"
import { nanoid } from "nanoid"
import type { AutomationConfig, AutomationGraph, SubgraphParamType } from "showrunner-schema"

export const SUBGRAPH_PARAM_TYPES: SubgraphParamType[] = ["string", "number", "boolean", "array", "object", "color", "any"]

interface UseSubgraphManagementOptions {
	model: Ref<AutomationConfig>
	focusedSubgraphId: Ref<string | undefined>
	activeSubgraphId: Ref<string | undefined>
	subgraphsOpen: Ref<boolean>
	clearSelection: () => void
	closeContextMenu: () => void
	commitUndo: () => void
}

export function useSubgraphManagement(options: UseSubgraphManagementOptions) {
	const {
		model,
		focusedSubgraphId,
		activeSubgraphId,
		subgraphsOpen,
		clearSelection,
		closeContextMenu,
		commitUndo,
	} = options

	const subgraphsList = computed(() => model.value.subgraphs ?? [])
	const activeSubgraph = computed(() => {
		if (!activeSubgraphId.value) return undefined
		return model.value.subgraphs?.find((subgraph) => subgraph.id === activeSubgraphId.value)
	})
	const isEditingSubgraph = computed(() => Boolean(activeSubgraph.value))
	const activeGraph = computed<AutomationGraph | undefined>(() => activeSubgraph.value ?? model.value.graph)

	function findSubgraph(id: string) {
		return model.value.subgraphs?.find((subgraph) => subgraph.id === id)
	}

	function addSubgraph() {
		if (!model.value.subgraphs) model.value.subgraphs = []
		const id = nanoid()
		model.value.subgraphs.push({
			id,
			name: `Subgraph ${model.value.subgraphs.length + 1}`,
			parameters: [],
			outputs: [],
			nodes: [],
			edges: [],
			dataWires: [],
			entryNodeId: "",
		})
		focusedSubgraphId.value = id
		subgraphsOpen.value = true
		commitUndo()
	}

	function focusSubgraph(id: string) {
		const subgraph = findSubgraph(id)
		if (!subgraph) return
		focusedSubgraphId.value = id
		subgraphsOpen.value = true
	}

	function openSubgraphCanvas(id: string) {
		const subgraph = findSubgraph(id)
		if (!subgraph) return
		focusedSubgraphId.value = id
		activeSubgraphId.value = id
		subgraph.dataWires ??= []
		clearSelection()
		closeContextMenu()
		subgraphsOpen.value = true
	}

	function openMainCanvas() {
		activeSubgraphId.value = undefined
		clearSelection()
	}

	function deleteSubgraph(id: string) {
		if (!model.value.subgraphs) return
		const idx = model.value.subgraphs.findIndex((s) => s.id === id)
		if (idx < 0) return
		model.value.subgraphs.splice(idx, 1)
		if (model.value.graph) {
			model.value.graph.nodes = model.value.graph.nodes.filter(
				(n) => !(n.type === "subgraphCall" && n.subgraphId === id)
			)
		}
		for (const subgraph of model.value.subgraphs ?? []) {
			subgraph.nodes = subgraph.nodes.filter((n) => !(n.type === "subgraphCall" && n.subgraphId === id))
		}
		if (focusedSubgraphId.value === id) focusedSubgraphId.value = undefined
		if (activeSubgraphId.value === id) activeSubgraphId.value = undefined
		commitUndo()
	}

	function updateSubgraphName(id: string, name: string) {
		const subgraph = findSubgraph(id)
		if (!subgraph) return
		subgraph.name = name.trim() || "Unnamed Subgraph"
		commitUndo()
	}

	function addSubgraphParam(id: string, collection: "parameters" | "outputs") {
		const subgraph = findSubgraph(id)
		if (!subgraph) return
		const prefix = collection === "parameters" ? "input" : "output"
		subgraph[collection].push({
			name: `${prefix}${subgraph[collection].length + 1}`,
			type: "string",
			default: collection === "parameters" ? "" : undefined,
		})
		focusedSubgraphId.value = id
		commitUndo()
	}

	function deleteSubgraphParam(id: string, collection: "parameters" | "outputs", index: number) {
		const subgraph = findSubgraph(id)
		if (!subgraph) return
		subgraph[collection].splice(index, 1)
		focusedSubgraphId.value = id
		commitUndo()
	}

	function updateSubgraphParam(
		id: string,
		collection: "parameters" | "outputs",
		index: number,
		field: "name" | "type" | "default",
		value: string
	) {
		const subgraph = findSubgraph(id)
		const param = subgraph?.[collection][index]
		if (!subgraph || !param) return
		if (field === "name") {
			param.name = value.trim() || `${collection === "parameters" ? "input" : "output"}${index + 1}`
		} else if (field === "type") {
			param.type = SUBGRAPH_PARAM_TYPES.includes(value as SubgraphParamType) ? value as SubgraphParamType : "any"
			if (collection === "parameters") param.default = coerceSubgraphDefault(param.type, param.default)
		} else if (collection === "parameters") {
			param.default = coerceSubgraphDefault(param.type, value)
		}
		focusedSubgraphId.value = id
		commitUndo()
	}

	return {
		subgraphsList,
		activeSubgraph,
		isEditingSubgraph,
		activeGraph,
		addSubgraph,
		focusSubgraph,
		openSubgraphCanvas,
		openMainCanvas,
		deleteSubgraph,
		updateSubgraphName,
		addSubgraphParam,
		deleteSubgraphParam,
		updateSubgraphParam,
		coerceSubgraphDefault,
	}
}

export function coerceSubgraphDefault(type: SubgraphParamType, value: unknown) {
	if (type === "number") {
		const numberValue = Number(value)
		return Number.isFinite(numberValue) ? numberValue : 0
	}
	if (type === "boolean") return value === true || String(value).toLowerCase() === "true"
	if (type === "array") {
		if (Array.isArray(value)) return value
		try {
			const parsed = JSON.parse(String(value || "[]"))
			return Array.isArray(parsed) ? parsed : []
		} catch {
			return []
		}
	}
	if (type === "object") {
		if (value && typeof value === "object" && !Array.isArray(value)) return value
		try {
			const parsed = JSON.parse(String(value || "{}"))
			return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {}
		} catch {
			return {}
		}
	}
	return value == null ? "" : String(value)
}
