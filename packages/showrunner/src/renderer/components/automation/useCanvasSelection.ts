import type { ComputedRef, Ref } from "vue"
import { useGraphSelection } from "../../../../../../libs/showrunner-ui-core/src/util/graph"
import type { NodePosition } from "./useNodeCanvas"
import { NODE_WIDTH, type NodeData } from "./useNodeRendering"

export interface RubberBand {
	x: number
	y: number
	width: number
	height: number
}

interface UseCanvasSelectionOptions {
	nodes: ComputedRef<NodeData[]>
	canvasRef: Ref<HTMLElement | undefined>
	selectedNodeId: Ref<string | undefined>
	selectedNodeIds: Ref<Set<string>>
	selectedAnnotationBlockId: Ref<string | undefined>
	selectedEdgeId: Ref<string | undefined>
	selectedDataWireId: Ref<string | undefined>
	detailsOpen: Ref<boolean>
	spaceHeld: Ref<boolean>
	rubberBand: Ref<RubberBand | null>
	contextMenuOpen: () => boolean
	closeContextMenu: () => void
	startPan: (event: PointerEvent) => void
	getCanvasPointFromClientPosition: (clientX: number, clientY: number) => NodePosition
}

export function useCanvasSelection(options: UseCanvasSelectionOptions) {
	const {
		nodes,
		canvasRef,
		selectedNodeId,
		selectedNodeIds,
		selectedAnnotationBlockId,
		selectedEdgeId,
		selectedDataWireId,
		detailsOpen,
		spaceHeld,
		rubberBand,
		contextMenuOpen,
		closeContextMenu,
		startPan,
		getCanvasPointFromClientPosition,
	} = options
	const graphSelection = useGraphSelection({
		selectedNodeId,
		selectedNodeIds,
		getNodeIds: () => nodes.value.map((node) => node.id),
	})

	function selectNode(event: MouseEvent | PointerEvent, nodeId: string) {
		selectedEdgeId.value = undefined
		selectedDataWireId.value = undefined
		selectedAnnotationBlockId.value = undefined
		if (event.ctrlKey || event.metaKey) {
			graphSelection.toggleNodeSelection(nodeId)
			return
		}
		focusNode(nodeId)
	}

	function focusNode(nodeId: string) {
		graphSelection.selectOnlyNode(nodeId)
		selectedEdgeId.value = undefined
		selectedAnnotationBlockId.value = undefined
	}

	function clearSelection() {
		graphSelection.clearNodeSelection()
		selectedEdgeId.value = undefined
		selectedDataWireId.value = undefined
		selectedAnnotationBlockId.value = undefined
	}

	function clearNodeSelection() {
		graphSelection.clearNodeSelection()
		selectedAnnotationBlockId.value = undefined
	}

	function selectAnnotationBlock(blockId: string) {
		selectedNodeId.value = undefined
		selectedEdgeId.value = undefined
		selectedDataWireId.value = undefined
		selectedAnnotationBlockId.value = blockId
		detailsOpen.value = true
	}

	function handleCanvasPointerDown(event: PointerEvent) {
		const target = event.target as HTMLElement
		if (target.closest(".node-automation__context-menu")) return
		if (contextMenuOpen()) closeContextMenu()
		if (target.closest(".node-automation__canvas-controls")) return

		const isCanvasTarget =
			target.classList.contains("node-automation__canvas") ||
			target.classList.contains("node-automation__surface") ||
			target.classList.contains("node-automation__edges")

		if (isCanvasTarget) clearSelection()
		if (event.button === 1 && isCanvasTarget) {
			event.preventDefault()
			startPan(event)
		}
		if (event.button === 0 && isCanvasTarget && spaceHeld.value) {
			event.preventDefault()
			startPan(event)
		} else if (event.button === 0 && isCanvasTarget) {
			selectedEdgeId.value = undefined
			selectedDataWireId.value = undefined
			startRubberBand(event)
		}
	}

	function startRubberBand(event: PointerEvent) {
		const canvas = canvasRef.value
		if (!canvas) return

		const origin = getCanvasPointFromClientPosition(event.clientX, event.clientY)
		const startX = event.clientX
		const startY = event.clientY
		let didMove = false

		canvas.setPointerCapture(event.pointerId)

		function onMove(moveEvent: PointerEvent) {
			const dx = Math.abs(moveEvent.clientX - startX)
			const dy = Math.abs(moveEvent.clientY - startY)
			if (!didMove && dx < 4 && dy < 4) return
			didMove = true

			const current = getCanvasPointFromClientPosition(moveEvent.clientX, moveEvent.clientY)
			const x = Math.min(origin.x, current.x)
			const y = Math.min(origin.y, current.y)
			const width = Math.abs(current.x - origin.x)
			const height = Math.abs(current.y - origin.y)
			rubberBand.value = { x, y, width, height }

			const ids = new Set<string>()
			for (const node of nodes.value) {
				const nodeRight = node.x + (node.width ?? NODE_WIDTH)
				const nodeBottom = node.y + node.height
				if (node.x < x + width && nodeRight > x && node.y < y + height && nodeBottom > y) {
					ids.add(node.id)
				}
			}
			graphSelection.setSelectedNodeIds(ids)
		}

		function onUp(upEvent: PointerEvent) {
			canvas.releasePointerCapture(upEvent.pointerId)
			canvas.removeEventListener("pointermove", onMove)
			canvas.removeEventListener("pointerup", onUp)
			canvas.removeEventListener("pointercancel", onUp)
			rubberBand.value = null
		}

		canvas.addEventListener("pointermove", onMove)
		canvas.addEventListener("pointerup", onUp)
		canvas.addEventListener("pointercancel", onUp)
	}

	return {
		selectNode,
		focusNode,
		clearSelection,
		clearNodeSelection,
		selectAnnotationBlock,
		handleCanvasPointerDown,
	}
}
