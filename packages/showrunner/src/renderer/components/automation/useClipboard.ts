/**
 * Composable for copy/cut/paste in the node editor.
 * Extracted from NodeAutomationEdit.vue.
 */
import { type Ref } from "vue"
import { nanoid } from "nanoid"
import {
	AnyAction,
	ActionStack,
	AutomationConfig,
	isActionStack,
	findActionAndSequenceById,
	assignNewIds,
	type AutomationDataWire,
	type AutomationVariableNode,
} from "ShowRunner-schema"
import type { NodePosition } from "./useNodeCanvas"
import type { NodeData } from "./useNodeRendering"

interface ClipboardPayload {
	actions?: (AnyAction | ActionStack)[]
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
	cloneActionForNodeEditor: (action: AnyAction | ActionStack) => AnyAction | ActionStack,
) {
	let inMemoryClipboard = ""

	function copySelectedNodes() {
		const actions: (AnyAction | ActionStack)[] = []
		const copiedVarNodes: AutomationVariableNode[] = []
		const selectedIds = new Set(selectedNodeIds.value)

		for (const id of selectedIds) {
			if (id === "trigger") continue
			const info = findActionAndSequenceById(id, model.value)
			if (info) {
				actions.push(structuredClone(info.action))
			} else {
				const vn = variableNodes.value.find((v) => v.id === id)
				if (vn) copiedVarNodes.push(structuredClone(vn))
			}
		}

		const copiedWires = dataWires.value.filter(
			(w) => selectedIds.has(w.fromNode) && selectedIds.has(w.toNode)
		).map((w) => structuredClone(w))

		if (actions.length === 0 && copiedVarNodes.length === 0) return
		const payload = JSON.stringify({ actions, variableNodes: copiedVarNodes, wires: copiedWires })
		inMemoryClipboard = payload
		navigator.clipboard.writeText(payload).catch(() => {})
		logActivity("Copied", `${actions.length + copiedVarNodes.length} node${(actions.length + copiedVarNodes.length) === 1 ? "" : "s"}`)
	}

	function cutSelectedNodes() {
		copySelectedNodes()
		const idsToDelete = [...selectedNodeIds.value].filter((id) => id !== "trigger")
		for (const id of idsToDelete) {
			// Try action node
			const info = findActionAndSequenceById(id, model.value)
			if (info) {
				const idx = info.sequence.actions.findIndex((item) => {
					if (isActionStack(item)) return item.id === id
					return (item as AnyAction).id === id
				})
				if (idx >= 0) info.sequence.actions.splice(idx, 1)
			} else {
				// Try variable node
				const vnIdx = variableNodes.value.findIndex((v) => v.id === id)
				if (vnIdx >= 0) variableNodes.value.splice(vnIdx, 1)
			}
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
				(!Array.isArray(parsed?.actions) || parsed.actions.length === 0) &&
				(!Array.isArray(parsed?.variableNodes) || parsed.variableNodes.length === 0)
			) return

			const surface = canvasRef.value?.querySelector<HTMLElement>(".node-automation__surface")
			const rect = surface?.getBoundingClientRect()
			const viewCenterX = rect ? (rect.width / 2) / zoomRef.value : 400
			const viewCenterY = rect ? (rect.height / 2) / zoomRef.value : 300

			const idMap = new Map<string, string>()
			const newIds: string[] = []

			for (const action of parsed.actions ?? []) {
				const cloned = cloneActionForNodeEditor(action)
				idMap.set(action.id, cloned.id)
				model.value.sequence.actions.push(cloned)
				const pos = nodePositions.value[cloned.id]
				if (pos) {
					pos.x += 40
					pos.y += 40
				}
				newIds.push(cloned.id)
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
