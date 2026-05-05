import type { ComputedRef, Ref } from "vue"
import { computeNodeHeight, NODE_WIDTH, type NodeData } from "./useNodeRendering"

interface UseNodeResizeOptions {
	nodeSizes: ComputedRef<Record<string, { width?: number; height?: number }>>
	zoom: Ref<number>
	commitUndo: () => void
}

export function useNodeResize(options: UseNodeResizeOptions) {
	const { nodeSizes, zoom, commitUndo } = options

	function startResize(event: PointerEvent, node: NodeData) {
		event.preventDefault()
		const startX = event.clientX
		const startY = event.clientY
		const startWidth = node.width ?? NODE_WIDTH
		const startHeight = node.height
		const target = event.currentTarget as HTMLElement
		target.setPointerCapture(event.pointerId)

		const allPorts = [...(node.inputPorts ?? []), ...(node.outputPorts ?? [])]
		const maxLabelLen = allPorts.reduce((max, port) => Math.max(max, port.label.length), 0)
		const minWidth = Math.max(120, 80 + maxLabelLen * 7)
		const minHeight = computeNodeHeight(node.configLines, node.inputPorts, node.outputPorts)

		function onMove(moveEvent: PointerEvent) {
			const dx = (moveEvent.clientX - startX) / zoom.value
			const dy = (moveEvent.clientY - startY) / zoom.value
			const newWidth = Math.max(minWidth, Math.round(startWidth + dx))
			const newHeight = Math.max(minHeight, Math.round(startHeight + dy))
			nodeSizes.value[node.id] = { ...(nodeSizes.value[node.id] ?? {}), width: newWidth, height: newHeight }
		}

		function onUp() {
			target.removeEventListener("pointermove", onMove)
			target.removeEventListener("pointerup", onUp)
			commitUndo()
		}

		target.addEventListener("pointermove", onMove)
		target.addEventListener("pointerup", onUp)
	}

	return {
		startResize,
	}
}
