import type { ComputedRef, Ref } from "vue"
import type { NodePosition } from "./useNodeCanvas"

interface DraggableNode extends NodePosition {
	id: string
}

export function useNodeDrag(
	nodePositions: ComputedRef<Record<string, NodePosition>>,
	selectedNodeId: Ref<string | undefined>,
	zoom: Ref<number>,
	snapCoordinate: (value: number) => number,
	closeContextMenu: () => void,
	commitUndo: () => void
) {
	function startDrag(event: PointerEvent, node: DraggableNode) {
		closeContextMenu()
		selectedNodeId.value = node.id
		const startX = event.clientX
		const startY = event.clientY
		const initial = nodePositions.value[node.id] ?? { x: node.x, y: node.y }
		const target = event.currentTarget as HTMLElement
		target.setPointerCapture(event.pointerId)

		function onMove(moveEvent: PointerEvent) {
			const nextX = Math.max(12, initial.x + (moveEvent.clientX - startX) / zoom.value)
			const nextY = Math.max(12, initial.y + (moveEvent.clientY - startY) / zoom.value)
			nodePositions.value[node.id] = {
				x: snapCoordinate(nextX),
				y: snapCoordinate(nextY),
			}
		}

		function onUp(upEvent: PointerEvent) {
			const moved = nodePositions.value[node.id]
			target.releasePointerCapture(upEvent.pointerId)
			target.removeEventListener("pointermove", onMove)
			target.removeEventListener("pointerup", onUp)
			target.removeEventListener("pointercancel", onUp)
			if (moved && (moved.x !== initial.x || moved.y !== initial.y)) {
				commitUndo()
			}
		}

		target.addEventListener("pointermove", onMove)
		target.addEventListener("pointerup", onUp)
		target.addEventListener("pointercancel", onUp)
	}

	function resetSelectedNodePosition() {
		if (!selectedNodeId.value) return
		if (!nodePositions.value[selectedNodeId.value]) return
		delete nodePositions.value[selectedNodeId.value]
		commitUndo()
	}

	return {
		startDrag,
		resetSelectedNodePosition,
	}
}
