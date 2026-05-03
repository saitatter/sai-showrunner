/**
 * Composable for execution edge (flow wire) dragging in the node editor.
 * Extracted from NodeAutomationEdit.vue.
 */
import { computed, ref, type Ref } from "vue"
import { nanoid } from "nanoid"
import type { AutomationGraph } from "showrunner-schema"
import type { NodeData } from "./useNodeRendering"
import { NODE_WIDTH, NODE_BASE_HEIGHT } from "./useNodeRendering"

interface ExecEdgeDragState {
	fromNode: string
	fromPort: string | undefined
	fromX: number
	fromY: number
	startClientX: number
	startClientY: number
	currentX: number
	currentY: number
}

export function useExecEdges(
	graphRef: Ref<AutomationGraph | undefined>,
	nodesRef: Ref<NodeData[]>,
	canvasRef: Ref<HTMLElement | undefined>,
	zoomRef: Ref<number>,
	commitUndo: () => void,
	onDropOnEmpty?: (drop: { fromNode: string; fromPort?: string; canvasPoint: { x: number; y: number }; clientPoint: { x: number; y: number } }) => void
) {
	const execEdgeDrag = ref<ExecEdgeDragState | null>(null)

	const execDragWirePath = computed(() => {
		const drag = execEdgeDrag.value
		if (!drag) return null
		const x1 = drag.fromX
		const y1 = drag.fromY
		const x2 = drag.currentX
		const y2 = drag.currentY
		const cp = Math.max(60, Math.abs(x2 - x1) * 0.4)
		return `M ${x1} ${y1} C ${x1 + cp} ${y1}, ${x2 - cp} ${y2}, ${x2} ${y2}`
	})

	function startExecEdgeDrag(nodeId: string, port: string | undefined, event: PointerEvent) {
		if (!graphRef.value) return
		event.stopPropagation()
		event.preventDefault()

		const node = nodesRef.value.find((n) => n.id === nodeId)
		if (!node) return
		if (node.kind === "variable") return

		let fromX: number
		let fromY: number
		if (port && node.outputPorts) {
			const idx = node.outputPorts.findIndex((p) => p.key === port)
			const configHeight = (node.configLines?.length ?? 0) > 0 ? (node.configLines!.length * 20 + 4) : 0
			const portsStartY = NODE_BASE_HEIGHT + configHeight + 8
			fromX = node.x + (node.width ?? NODE_WIDTH)
			fromY = node.y + portsStartY + idx * 18 + 9
		} else {
			fromX = node.x + (node.width ?? NODE_WIDTH) + 6
			fromY = node.y + node.height / 2
		}

		execEdgeDrag.value = {
			fromNode: nodeId,
			fromPort: port,
			fromX,
			fromY,
			startClientX: event.clientX,
			startClientY: event.clientY,
			currentX: fromX,
			currentY: fromY,
		}

		window.addEventListener("pointermove", onExecEdgeMove)
		window.addEventListener("pointerup", onExecEdgeEnd)
	}

	function onExecEdgeMove(event: PointerEvent) {
		if (!execEdgeDrag.value || !canvasRef.value) return
		const surface = canvasRef.value.querySelector<HTMLElement>(".node-automation__surface")
		if (!surface) return
		const rect = surface.getBoundingClientRect()
		execEdgeDrag.value.currentX = (event.clientX - rect.left) / zoomRef.value
		execEdgeDrag.value.currentY = (event.clientY - rect.top) / zoomRef.value
	}

	function onExecEdgeEnd(event: PointerEvent) {
		window.removeEventListener("pointermove", onExecEdgeMove)
		window.removeEventListener("pointerup", onExecEdgeEnd)

		const drag = execEdgeDrag.value
		if (!drag || !graphRef.value) {
			execEdgeDrag.value = null
			return
		}
		updateDragPointFromEvent(drag, event)

		const targetNode = findExecEdgeTarget(drag)
		if (targetNode && targetNode !== drag.fromNode) {
			if (!wouldCreateExecCycle(drag.fromNode, targetNode)) {
				const g = graphRef.value
				const existingIdx = g.edges.findIndex(
					(e) => e.from === drag.fromNode && (e.port ?? undefined) === drag.fromPort
				)
				if (existingIdx >= 0) g.edges.splice(existingIdx, 1)

				g.edges.push({
					id: nanoid(),
					from: drag.fromNode,
					to: targetNode,
					port: drag.fromPort,
				})
				commitUndo()
			}
		} else if (onDropOnEmpty && didDragMove(drag, event)) {
			const clientPoint = { x: event.clientX, y: event.clientY }
			onDropOnEmpty({
				fromNode: drag.fromNode,
				fromPort: drag.fromPort,
				canvasPoint: { x: drag.currentX, y: drag.currentY },
				clientPoint,
			})
		}

		execEdgeDrag.value = null
	}

	function updateDragPointFromEvent(drag: ExecEdgeDragState, event: PointerEvent) {
		const surface = canvasRef.value?.querySelector<HTMLElement>(".node-automation__surface")
		const rect = surface?.getBoundingClientRect()
		if (!rect) return
		drag.currentX = (event.clientX - rect.left) / zoomRef.value
		drag.currentY = (event.clientY - rect.top) / zoomRef.value
	}

	function didDragMove(drag: ExecEdgeDragState, event: PointerEvent) {
		const dx = event.clientX - drag.startClientX
		const dy = event.clientY - drag.startClientY
		return Math.sqrt(dx * dx + dy * dy) > 8
	}

	function findExecEdgeTarget(drag: ExecEdgeDragState): string | undefined {
		const SNAP_RADIUS = 30
		for (const node of nodesRef.value) {
			if (node.id === drag.fromNode) continue
			if (node.id === "trigger") continue
			if (node.kind === "variable") continue
			const handleX = node.x - 6
			const handleY = node.y + node.height / 2
			const dx = drag.currentX - handleX
			const dy = drag.currentY - handleY
			if (Math.sqrt(dx * dx + dy * dy) < SNAP_RADIUS) {
				return node.id
			}
		}
		return undefined
	}

	function wouldCreateExecCycle(fromNode: string, toNode: string): boolean {
		if (!graphRef.value) return false
		const visited = new Set<string>()
		const stack = [toNode]
		while (stack.length > 0) {
			const current = stack.pop()!
			if (current === fromNode) return true
			if (visited.has(current)) continue
			visited.add(current)
			for (const edge of graphRef.value.edges) {
				if (edge.from === current) {
					stack.push(edge.to)
				}
			}
		}
		return false
	}

	function deleteExecEdge(edgeId: string) {
		if (!graphRef.value) return
		const idx = graphRef.value.edges.findIndex((e) => e.id === edgeId)
		if (idx >= 0) {
			graphRef.value.edges.splice(idx, 1)
			commitUndo()
		}
	}

	return {
		execEdgeDrag,
		execDragWirePath,
		startExecEdgeDrag,
		deleteExecEdge,
	}
}
