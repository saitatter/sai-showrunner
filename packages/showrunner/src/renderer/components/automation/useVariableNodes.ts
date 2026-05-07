import { computed, ref, type Ref } from "vue"
import { nanoid } from "nanoid"
import type { AutomationConfig, AutomationDataWire, AutomationVariableNode } from "showrunner-schema"
import type { NodePosition } from "./useNodeCanvas"
import { computeNodeHeight, type NodeData } from "./useNodeRendering"
import type { PortDef } from "./usePortConnections"

export type VariableNodeType = "string" | "number" | "boolean" | "color"

interface UseVariableNodesOptions {
	model: Ref<AutomationConfig>
	nodePositions: Ref<Record<string, NodePosition>>
	nodeSizes: Ref<Record<string, { width?: number; height?: number }>>
	dataWires: Ref<AutomationDataWire[]>
	selectedNodeId: Ref<string | undefined>
	getContextMenuCanvasPoint: () => NodePosition
	closeContextMenu: () => void
	commitUndo: () => void
}

const VARIABLE_TYPE_INFO: Record<VariableNodeType, { icon: string; portType: string; color: string }> = {
	string: { icon: "mdi mdi-format-text", portType: "str", color: "#81c784" },
	number: { icon: "mdi mdi-numeric", portType: "num", color: "#4fc3f7" },
	boolean: { icon: "mdi mdi-toggle-switch-outline", portType: "bool", color: "#ffb74d" },
	color: { icon: "mdi mdi-palette", portType: "color", color: "#f06292" },
}

const VARIABLE_DEFAULTS: Record<VariableNodeType, string | number | boolean> = {
	string: "",
	number: 0,
	boolean: true,
	color: "#ffffff",
}

export function useVariableNodes({
	model,
	nodePositions,
	nodeSizes,
	dataWires,
	selectedNodeId,
	getContextMenuCanvasPoint,
	closeContextMenu,
	commitUndo,
}: UseVariableNodesOptions) {
	const variableNodes = computed({
		get: () => {
			if (!model.value) return []
			model.value.variableNodes ??= []
			return model.value.variableNodes!
		},
		set: (value: AutomationVariableNode[]) => {
			if (!model.value) return
			model.value.variableNodes = value
		},
	})

	const variableNodeData = computed<NodeData[]>(() =>
		variableNodes.value.map((variableNode) => {
			const info = VARIABLE_TYPE_INFO[variableNode.type] ?? VARIABLE_TYPE_INFO.string
			const pos = nodePositions.value[variableNode.id] ?? { x: variableNode.x, y: variableNode.y }
			const inputPorts: PortDef[] = [{ key: "value", label: "set", type: info.portType }]
			const outputPorts: PortDef[] = [{ key: "value", label: "value", type: info.portType }]
			return {
				id: variableNode.id,
				kind: "variable" as const,
				title: variableNode.name || variableNode.type.charAt(0).toUpperCase() + variableNode.type.slice(1),
				subtitle: String(variableNode.value),
				icon: info.icon,
				badge: info.portType,
				x: pos.x,
				y: pos.y,
				inputPorts,
				outputPorts,
				height: Math.max(computeNodeHeight(undefined, inputPorts, outputPorts), nodeSizes.value[variableNode.id]?.height ?? 0),
				width: nodeSizes.value[variableNode.id]?.width ?? 160,
			}
		})
	)

	const selectedVariableNode = computed(() => {
		if (!selectedNodeId.value) return undefined
		return variableNodes.value.find((node) => node.id === selectedNodeId.value)
	})

	const inlineEditNodeId = ref<string>()

	function addVariableNode(type: VariableNodeType) {
		const canvasPoint = getContextMenuCanvasPoint()
		const variableNode: AutomationVariableNode = {
			id: nanoid(),
			name: "",
			type,
			value: VARIABLE_DEFAULTS[type],
			x: canvasPoint.x,
			y: canvasPoint.y,
		}
		variableNodes.value.push(variableNode)
		closeContextMenu()
		commitUndo()
	}

	function deleteVariableNode(id: string) {
		const index = variableNodes.value.findIndex((variableNode) => variableNode.id === id)
		if (index < 0) return
		variableNodes.value.splice(index, 1)
		dataWires.value = dataWires.value.filter((wire) => wire.fromNode !== id && wire.toNode !== id)
		commitUndo()
	}

	function updateVariableNodeValue(id: string, value: string | number | boolean) {
		const variableNode = variableNodes.value.find((node) => node.id === id)
		if (!variableNode) return
		variableNode.value = value
		commitUndo()
	}

	function updateSelectedVariableNodeValue(value: string | number | boolean) {
		const id = selectedVariableNode.value?.id
		if (!id) return
		updateVariableNodeValue(id, value)
	}

	function updateVariableNodeName(id: string, name: string) {
		const variableNode = variableNodes.value.find((node) => node.id === id)
		if (!variableNode) return
		variableNode.name = name
		commitUndo()
	}

	function updateSelectedVariableNodeName(name: string) {
		const id = selectedVariableNode.value?.id
		if (!id) return
		updateVariableNodeName(id, name)
	}

	function startInlineEdit(nodeId: string) {
		inlineEditNodeId.value = nodeId
	}

	function commitInlineEdit(event: Event, node: NodeData) {
		const input = event.target as HTMLInputElement
		const variableNode = variableNodes.value.find((item) => item.id === node.id)
		if (variableNode) {
			const raw = input.value
			if (variableNode.type === "number") {
				const num = Number(raw)
				if (!isNaN(num)) variableNode.value = num
			} else if (variableNode.type === "boolean") {
				variableNode.value = raw === "true" || raw === "1"
			} else {
				variableNode.value = raw
			}
			commitUndo()
		}
		inlineEditNodeId.value = undefined
	}

	function cancelInlineEdit() {
		inlineEditNodeId.value = undefined
	}

	return {
		variableNodes,
		variableNodeData,
		selectedVariableNode,
		inlineEditNodeId,
		addVariableNode,
		deleteVariableNode,
		updateSelectedVariableNodeValue,
		updateSelectedVariableNodeName,
		startInlineEdit,
		commitInlineEdit,
		cancelInlineEdit,
	}
}
