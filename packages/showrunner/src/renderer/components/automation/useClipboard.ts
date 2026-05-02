/**
 * Composable for copy/cut/paste in the node editor.
 * Extracted from NodeAutomationEdit.vue.
 */
import { type Ref } from "vue"
import { nanoid } from "nanoid"
import { useAppFeedback } from "ShowRunner-ui-core"
import {
	AutomationConfig,
	type AutomationDataWire,
	type AutomationVariableNode,
	type GraphEdge,
	type GraphNode,
} from "ShowRunner-schema"
import type { NodePosition } from "./useNodeCanvas"
import type { NodeData } from "./useNodeRendering"

interface ClipboardPayload {
	graphNodes?: GraphNode[]
	graphEdges?: GraphEdge[]
	variableNodes?: AutomationVariableNode[]
	wires?: AutomationDataWire[]
}

export function useClipboard(
	model: Ref<AutomationConfig>,
	selectedNodeIds: Ref<Set<string>>,
	selectedNodeId: Ref<string | undefined>,
	variableNodes: Ref<AutomationVariableNode[]>,
	dataWires: Ref<AutomationDataWire[]>,
	nodePositions: Ref<Record<string, NodePosition>>,
	canvasRef: Ref<HTMLElement | undefined>,
	zoomRef: Ref<number>,
	commitUndo: () => void,
	logActivity: (action: string, detail: string) => void,
	clearSelection: () => void,
) {
	let inMemoryClipboard = ""
	const feedback = useAppFeedback("Node Editor")

	function copySelectedNodes() {
		const graphNodes: GraphNode[] = []
		const copiedVarNodes: AutomationVariableNode[] = []
		const selectedIds = new Set(selectedNodeIds.value)

		for (const id of selectedIds) {
			if (id === "trigger") continue
			const node = model.value.graph?.nodes.find((graphNode) => graphNode.id === id)
			if (node) graphNodes.push(structuredClone(node))
			const vn = variableNodes.value.find((v) => v.id === id)
			if (vn) copiedVarNodes.push(structuredClone(vn))
		}

		const copiedWires = dataWires.value.filter(
			(w) => selectedIds.has(w.fromNode) && selectedIds.has(w.toNode)
		).map((w) => structuredClone(w))
		const copiedEdges = (model.value.graph?.edges ?? []).filter(
			(edge) => selectedIds.has(edge.from) && selectedIds.has(edge.to)
		).map((edge) => structuredClone(edge))

		if (graphNodes.length === 0 && copiedVarNodes.length === 0) return
		const payload = JSON.stringify({ graphNodes, graphEdges: copiedEdges, variableNodes: copiedVarNodes, wires: copiedWires })
		inMemoryClipboard = payload
		navigator.clipboard.writeText(payload).catch((err) => {
			feedback.warn("Using in-memory clipboard fallback", err instanceof Error ? err.message : String(err), 2500)
		})
		logActivity("Copied", `${graphNodes.length + copiedVarNodes.length} node${(graphNodes.length + copiedVarNodes.length) === 1 ? "" : "s"}`)
	}

	function cutSelectedNodes() {
		copySelectedNodes()
		const idsToDelete = [...selectedNodeIds.value].filter((id) => id !== "trigger")
		model.value.graph ??= { nodes: [], edges: [], entryNodeId: "" }
		for (const id of idsToDelete) {
			model.value.graph.nodes = model.value.graph.nodes.filter((node) => node.id !== id)
			model.value.graph.edges = model.value.graph.edges.filter((edge) => edge.from !== id && edge.to !== id)
			if (model.value.graph.entryNodeId === id) model.value.graph.entryNodeId = model.value.graph.nodes[0]?.id ?? ""
			const vnIdx = variableNodes.value.findIndex((v) => v.id === id)
			if (vnIdx >= 0) variableNodes.value.splice(vnIdx, 1)
			delete nodePositions.value[id]
			dataWires.value = dataWires.value.filter((w) => w.fromNode !== id && w.toNode !== id)
		}
		clearSelection()
		logActivity("Cut", `${idsToDelete.length} node${idsToDelete.length === 1 ? "" : "s"}`)
		commitUndo()
	}

	function pasteNodes() {
		const doPaste = (text: string) => {
			let parsed: ClipboardPayload
			try {
				parsed = JSON.parse(text)
			} catch {
				return
			}
			if (
				(!Array.isArray(parsed?.graphNodes) || parsed.graphNodes.length === 0) &&
				(!Array.isArray(parsed?.variableNodes) || parsed.variableNodes.length === 0)
			) return

			const surface = canvasRef.value?.querySelector<HTMLElement>(".node-automation__surface")
			const rect = surface?.getBoundingClientRect()
			const viewCenterX = rect ? (rect.width / 2) / zoomRef.value : 400
			const viewCenterY = rect ? (rect.height / 2) / zoomRef.value : 300

			const idMap = new Map<string, string>()
			const newIds: string[] = []
			model.value.graph ??= { nodes: [], edges: [], entryNodeId: "" }

			for (const node of parsed.graphNodes ?? []) {
				const newId = nanoid()
				idMap.set(node.id, newId)
				const cloned = {
					...structuredClone(node),
					id: newId,
					x: viewCenterX + (node.x - (parsed.graphNodes![0]?.x ?? 0)),
					y: viewCenterY + (node.y - (parsed.graphNodes![0]?.y ?? 0)),
				} as GraphNode
				model.value.graph.nodes.push(cloned)
				if (!model.value.graph.entryNodeId) model.value.graph.entryNodeId = cloned.id
				nodePositions.value[cloned.id] = { x: cloned.x, y: cloned.y }
				newIds.push(cloned.id)
			}

			for (const edge of parsed.graphEdges ?? []) {
				const newFrom = idMap.get(edge.from)
				const newTo = idMap.get(edge.to)
				if (newFrom && newTo) {
					model.value.graph.edges.push({
						id: `${newFrom}:${edge.port ?? "out"}:${newTo}`,
						from: newFrom,
						to: newTo,
						port: edge.port,
					})
				}
			}

			for (const vn of parsed.variableNodes ?? []) {
				const newId = nanoid()
				idMap.set(vn.id, newId)
				variableNodes.value.push({
					...vn,
					id: newId,
					x: viewCenterX + (vn.x - (parsed.variableNodes![0]?.x ?? 0)),
					y: viewCenterY + (vn.y - (parsed.variableNodes![0]?.y ?? 0)),
				})
				newIds.push(newId)
			}

			for (const wire of parsed.wires ?? []) {
				const newFrom = idMap.get(wire.fromNode)
				const newTo = idMap.get(wire.toNode)
				if (newFrom && newTo) {
					dataWires.value.push({
						id: `${newFrom}:${wire.fromPort}->${newTo}:${wire.toPort}`,
						fromNode: newFrom,
						fromPort: wire.fromPort,
						toNode: newTo,
						toPort: wire.toPort,
					})
				}
			}

			selectedNodeIds.value = new Set(newIds)
			selectedNodeId.value = newIds[0]
			logActivity("Pasted", `${newIds.length} node${newIds.length === 1 ? "" : "s"}`)
			commitUndo()
		}

		navigator.clipboard.readText().then(doPaste).catch(() => {
			if (inMemoryClipboard) doPaste(inMemoryClipboard)
		})
	}

	return {
		copySelectedNodes,
		cutSelectedNodes,
		pasteNodes,
	}
}
