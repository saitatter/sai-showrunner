import { computed, ref, type ComputedRef, type Ref } from "vue"
import type { AutomationDataWire, AutomationVariableNode, SubgraphDefinition } from "showrunner-schema"
import { areTypesCompatible, wouldCreateDataWireCycle, type DataWire, type PortDef } from "./usePortConnections"
import type { NodeData } from "./useNodeRendering"

interface UseDataWireHealthOptions {
	nodes: ComputedRef<NodeData[]>
	dataWires: Ref<AutomationDataWire[]>
	variableNodes: Ref<AutomationVariableNode[]>
	activeSubgraph: ComputedRef<SubgraphDefinition | undefined>
	activeTestExecution: ComputedRef<{ nodeResults?: Record<string, any> } | undefined>
	selectedEdgeId: Ref<string | undefined>
	selectedNodeId: Ref<string | undefined>
	selectedNodeIds: Ref<Set<string>>
	commitUndo: () => void
	nodeTitleById: (nodeId: string) => string
}

export function useDataWireHealth({
	nodes,
	dataWires,
	variableNodes,
	activeSubgraph,
	activeTestExecution,
	selectedEdgeId,
	selectedNodeId,
	selectedNodeIds,
	commitUndo,
	nodeTitleById,
}: UseDataWireHealthOptions) {
	const selectedDataWireId = ref<string>()

	const connectedPorts = computed(() => {
		const set = new Set<string>()
		for (const wire of dataWires.value) {
			set.add(`${wire.fromNode}:${wire.fromPort}:out`)
			set.add(`${wire.toNode}:${wire.toPort}:in`)
		}
		return set
	})

	const invalidDataWireIssues = computed(() => {
		return dataWires.value.flatMap((wire) => {
			const source = resolveDataWirePort(wire.fromNode, wire.fromPort, "out")
			const target = resolveDataWirePort(wire.toNode, wire.toPort, "in")
			if (!source) return [{ id: wire.id, message: `Missing source port: ${nodeTitleById(wire.fromNode)}.${wire.fromPort}` }]
			if (!target) return [{ id: wire.id, message: `Missing target port: ${nodeTitleById(wire.toNode)}.${wire.toPort}` }]
			if (!areTypesCompatible(source.type, target.type)) {
				return [{ id: wire.id, message: `Incompatible data wire: ${source.type} -> ${target.type}` }]
			}
			const otherWires = dataWires.value.filter((item) => item.id !== wire.id)
			if (wouldCreateDataWireCycle(otherWires, wire.fromNode, wire.toNode)) {
				return [{ id: wire.id, message: "Data wire creates a circular dependency." }]
			}
			return []
		})
	})

	function isPortConnected(nodeId: string, portKey: string, kind: "in" | "out"): boolean {
		return connectedPorts.value.has(`${nodeId}:${portKey}:${kind}`)
	}

	function resolveDataWirePort(nodeId: string, portKey: string, kind: "in" | "out") {
		if (kind === "out" && nodeId === "trigger") {
			const node = nodes.value.find((item) => item.id === nodeId)
			return node?.outputPorts?.find((port) => port.key === portKey)
		}
		if (kind === "out" && nodeId.startsWith("__param:")) {
			const paramName = nodeId.slice("__param:".length)
			const param = activeSubgraph.value?.parameters.find((item) => item.name === paramName)
			if (param && portKey === "value") return { key: portKey, label: param.name, type: param.type } satisfies PortDef
		}
		if (kind === "in" && nodeId.startsWith("__output:")) {
			const outputName = nodeId.slice("__output:".length)
			const output = activeSubgraph.value?.outputs.find((item) => item.name === outputName)
			if (output && portKey === "value") return { key: portKey, label: output.name, type: output.type } satisfies PortDef
		}
		const node = nodes.value.find((item) => item.id === nodeId)
		const ports = kind === "in" ? node?.inputPorts : node?.outputPorts
		return ports?.find((port) => port.key === portKey)
	}

	function selectDataWireIssue(issue: { id: string }) {
		selectedDataWireId.value = issue.id
		selectedEdgeId.value = undefined
		selectedNodeId.value = undefined
		selectedNodeIds.value = new Set()
	}

	function cleanupInvalidDataWires() {
		const invalidIds = new Set(invalidDataWireIssues.value.map((issue) => issue.id))
		if (!invalidIds.size) return
		dataWires.value = dataWires.value.filter((wire) => !invalidIds.has(wire.id))
		selectedDataWireId.value = undefined
		commitUndo()
	}

	function dataWireTitle(wire: DataWire & { validationMessage?: string }) {
		const value = getWireRuntimeValue(wire)
		const fromNode = nodeTitleById(wire.fromNode)
		const toNode = nodeTitleById(wire.toNode)
		const validation = "validationMessage" in wire && wire.validationMessage ? `\n${wire.validationMessage}` : ""
		if (value === undefined) return `${fromNode}.${wire.fromPort} -> ${toNode}.${wire.toPort}${validation}`
		return `${fromNode}.${wire.fromPort} -> ${toNode}.${wire.toPort}${validation}\nValue: ${summarizeRuntimeValue(value)}`
	}

	function getWireRuntimeValue(wire: DataWire) {
		const variable = variableNodes.value.find((node) => node.id === wire.fromNode)
		if (variable && wire.fromPort === "value") return variable.value

		const result = activeTestExecution.value?.nodeResults?.[wire.fromNode]
		return getRuntimePathValue(result, wire.fromPort)
	}

	function selectDataWire(wireId: string, clearNodeSelection: () => void) {
		clearNodeSelection()
		selectedEdgeId.value = undefined
		selectedDataWireId.value = wireId
	}

	return {
		selectedDataWireId,
		invalidDataWireIssues,
		isPortConnected,
		selectDataWireIssue,
		cleanupInvalidDataWires,
		dataWireTitle,
		selectDataWire,
	}
}

function getRuntimePathValue(source: any, path: string) {
	if (source == null) return undefined
	const parts = String(path || "")
		.replace(/\[(\d+)\]/g, ".$1")
		.split(".")
		.map((part) => part.trim())
		.filter(Boolean)
	let cursor = source
	for (const part of parts) {
		if (cursor == null) return undefined
		cursor = cursor[part]
	}
	return cursor
}

function summarizeRuntimeValue(value: unknown) {
	if (value == null) return String(value)
	if (typeof value === "string") return value.length > 80 ? `${value.slice(0, 77)}...` : value
	if (typeof value === "number" || typeof value === "boolean") return String(value)
	try {
		const text = JSON.stringify(value)
		return text.length > 120 ? `${text.slice(0, 117)}...` : text
	} catch {
		return String(value)
	}
}
