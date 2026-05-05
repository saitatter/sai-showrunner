import type { ComputedRef, Ref, WritableComputedRef } from "vue"
import { nanoid } from "nanoid"
import type {
	AutomationConfig,
	AutomationDataWire,
	AutomationGraph,
	Expression,
	SubgraphParamType,
} from "showrunner-schema"
import type { NodeData } from "./useNodeRendering"
import { coerceSubgraphDefault } from "./useSubgraphManagement"

interface UseSubgraphCollapseOptions {
	model: Ref<AutomationConfig>
	activeGraph: ComputedRef<AutomationGraph | undefined>
	selectedNodeIds: Ref<Set<string>>
	dataWires: WritableComputedRef<AutomationDataWire[]>
	nodes: ComputedRef<NodeData[]>
	focusedSubgraphId: Ref<string | undefined>
	subgraphsOpen: Ref<boolean>
	focusNode: (nodeId: string) => void
	commitUndo: () => void
}

export function useSubgraphCollapse(options: UseSubgraphCollapseOptions) {
	const {
		model,
		activeGraph,
		selectedNodeIds,
		dataWires,
		nodes,
		focusedSubgraphId,
		subgraphsOpen,
		focusNode,
		commitUndo,
	} = options

	function getPortType(nodeId: string, portKey: string, kind: "in" | "out") {
		const node = nodes.value.find((item) => item.id === nodeId)
		const ports = kind === "in" ? node?.inputPorts : node?.outputPorts
		return ports?.find((port) => port.key === portKey)?.type
	}

	function collapseSelectionToSubgraph() {
		const graph = activeGraph.value
		if (!graph) return
		const selectedGraphIds = new Set(
			[...selectedNodeIds.value].filter((id) => id !== "trigger" && graph.nodes.some((node) => node.id === id))
		)
		if (selectedGraphIds.size === 0) {
			return
		}

		if (!model.value.subgraphs) model.value.subgraphs = []
		commitUndo()

		const selectedNodes = graph.nodes.filter((node) => selectedGraphIds.has(node.id))
		const internalEdges = graph.edges.filter((edge) => selectedGraphIds.has(edge.from) && selectedGraphIds.has(edge.to))
		const incomingEdges = graph.edges.filter((edge) => !selectedGraphIds.has(edge.from) && selectedGraphIds.has(edge.to))
		const outgoingEdges = graph.edges.filter((edge) => selectedGraphIds.has(edge.from) && !selectedGraphIds.has(edge.to))
		const internalDataWires = dataWires.value.filter((wire) => selectedGraphIds.has(wire.fromNode) && selectedGraphIds.has(wire.toNode))
		const incomingDataWires = dataWires.value.filter((wire) => !selectedGraphIds.has(wire.fromNode) && selectedGraphIds.has(wire.toNode))
		const outgoingDataWires = dataWires.value.filter((wire) => selectedGraphIds.has(wire.fromNode) && !selectedGraphIds.has(wire.toNode))
		const entryNodeId = selectedGraphIds.has(graph.entryNodeId)
			? graph.entryNodeId
			: selectedNodes.find((node) => !internalEdges.some((edge) => edge.to === node.id))?.id ?? selectedNodes[0]?.id ?? ""
		const x = Math.round(selectedNodes.reduce((sum, node) => sum + (node.x ?? 0), 0) / selectedNodes.length)
		const y = Math.round(selectedNodes.reduce((sum, node) => sum + (node.y ?? 0), 0) / selectedNodes.length)
		const subgraphId = nanoid()
		const callNodeId = nanoid()
		const usedInputNames = new Set<string>()
		const usedOutputNames = new Set<string>()
		const generatedInputs = incomingDataWires.map((wire) => {
			const name = uniqueSubgraphPortName(wire.toPort, usedInputNames)
			const type = portTypeToSubgraphType(getPortType(wire.toNode, wire.toPort, "in"))
			return { wire, name, type }
		})
		const generatedOutputs = outgoingDataWires.map((wire) => {
			const name = uniqueSubgraphPortName(wire.fromPort, usedOutputNames)
			const type = portTypeToSubgraphType(getPortType(wire.fromNode, wire.fromPort, "out"))
			return { wire, name, type }
		})
		const generatedInputWires: AutomationDataWire[] = generatedInputs.map(({ wire, name }) => ({
			id: `${subgraphId}:param:${name}->${wire.toNode}:${wire.toPort}`,
			fromNode: `__param:${name}`,
			fromPort: "value",
			toNode: wire.toNode,
			toPort: wire.toPort,
		}))
		const callNodeInputs = Object.fromEntries(
			generatedInputs.map(({ name }) => [name, { type: "variable", name } satisfies Expression])
		)

		model.value.subgraphs.push({
			id: subgraphId,
			name: `Subgraph ${model.value.subgraphs.length + 1}`,
			parameters: generatedInputs.map(({ name, type }) => ({ name, type, default: coerceSubgraphDefault(type, undefined) })),
			outputs: generatedOutputs.map(({ wire, name, type }) => ({
				name,
				type,
				expression: { type: "port", nodeId: wire.fromNode, port: wire.fromPort },
			})),
			nodes: structuredClone(selectedNodes),
			edges: structuredClone(internalEdges),
			dataWires: [...structuredClone(internalDataWires), ...generatedInputWires],
			entryNodeId,
		})

		graph.nodes = [
			...graph.nodes.filter((node) => !selectedGraphIds.has(node.id)),
			{ id: callNodeId, type: "subgraphCall", x, y, subgraphId, inputs: callNodeInputs },
		]
		graph.edges = graph.edges.filter((edge) => !selectedGraphIds.has(edge.from) && !selectedGraphIds.has(edge.to))
		for (const edge of incomingEdges) {
			graph.edges.push({ id: `${edge.from}:${callNodeId}:${edge.port ?? "out"}`, from: edge.from, to: callNodeId, port: edge.port })
		}
		const firstOutgoing = outgoingEdges[0]
		if (firstOutgoing) {
			graph.edges.push({ id: `${callNodeId}:${firstOutgoing.to}`, from: callNodeId, to: firstOutgoing.to })
		}
		if (selectedGraphIds.has(graph.entryNodeId)) graph.entryNodeId = callNodeId
		dataWires.value = [
			...dataWires.value.filter((wire) => !selectedGraphIds.has(wire.fromNode) && !selectedGraphIds.has(wire.toNode)),
			...generatedInputs.map(({ wire, name }) => ({
				id: `${wire.fromNode}:${wire.fromPort}->${callNodeId}:${name}`,
				fromNode: wire.fromNode,
				fromPort: wire.fromPort,
				toNode: callNodeId,
				toPort: name,
			})),
			...generatedOutputs.map(({ wire, name }) => ({
				id: `${callNodeId}:${name}->${wire.toNode}:${wire.toPort}`,
				fromNode: callNodeId,
				fromPort: name,
				toNode: wire.toNode,
				toPort: wire.toPort,
			})),
		]
		focusedSubgraphId.value = subgraphId
		subgraphsOpen.value = true
		focusNode(callNodeId)
	}

	return {
		collapseSelectionToSubgraph,
	}
}

function sanitizeSubgraphPortName(value: string, fallback: string) {
	const cleaned = String(value || "")
		.replace(/\[(\d+)\]/g, "_$1")
		.replace(/[^a-zA-Z0-9_]/g, "_")
		.replace(/^_+|_+$/g, "")
	return cleaned || fallback
}

function uniqueSubgraphPortName(base: string, used: Set<string>) {
	let candidate = sanitizeSubgraphPortName(base, "port")
	let index = 2
	while (used.has(candidate)) {
		candidate = `${sanitizeSubgraphPortName(base, "port")}${index}`
		index += 1
	}
	used.add(candidate)
	return candidate
}

function portTypeToSubgraphType(type: string | undefined): SubgraphParamType {
	switch (String(type || "any").toLowerCase()) {
		case "str":
		case "string":
			return "string"
		case "num":
		case "number":
			return "number"
		case "bool":
		case "boolean":
			return "boolean"
		case "list":
		case "array":
			return "array"
		case "obj":
		case "object":
			return "object"
		case "color":
			return "color"
		default:
			return "any"
	}
}
