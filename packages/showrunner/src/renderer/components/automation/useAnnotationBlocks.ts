import { computed, type ComputedRef, type Ref } from "vue"
import { nanoid } from "nanoid"
import type { NodePosition } from "./useNodeCanvas"
import type { NodeData } from "./useNodeRendering"

export interface AnnotationBlock {
	id: string
	label: string
	color: string
	x: number
	y: number
	width: number
	height: number
}

interface AnnotationBlockView {
	annotationBlocks?: AnnotationBlock[]
}

interface UseAnnotationBlocksOptions {
	view: Ref<AnnotationBlockView>
	nodes: ComputedRef<NodeData[]>
	selectedNodeIds: Ref<Set<string>>
	selectedAnnotationBlockId: Ref<string | undefined>
	getZoom: () => number
	snapCoordinate: (value: number) => number
	getViewport: () => { x: number; y: number }
	selectAnnotationBlock: (blockId: string) => void
	commitUndo: () => void
}

export function useAnnotationBlocks({
	view,
	nodes,
	selectedNodeIds,
	selectedAnnotationBlockId,
	getZoom,
	snapCoordinate,
	getViewport,
	selectAnnotationBlock,
	commitUndo,
}: UseAnnotationBlocksOptions) {
	const annotationBlocks = computed(() => {
		view.value.annotationBlocks ??= []
		return view.value.annotationBlocks
	})

	const selectedAnnotationBlock = computed(() =>
		annotationBlocks.value.find((block) => block.id === selectedAnnotationBlockId.value)
	)

	function addAnnotationBlock() {
		const selected = nodes.value.filter((node) => selectedNodeIds.value.has(node.id))
		const padding = 28
		let x: number
		let y: number
		let width: number
		let height: number

		if (selected.length) {
			const minX = Math.min(...selected.map((node) => node.x))
			const minY = Math.min(...selected.map((node) => node.y))
			const maxX = Math.max(...selected.map((node) => node.x + (node.width ?? 220)))
			const maxY = Math.max(...selected.map((node) => node.y + node.height))
			x = snapCoordinate(minX - padding)
			y = snapCoordinate(minY - padding - 18)
			width = Math.max(240, maxX - minX + padding * 2)
			height = Math.max(140, maxY - minY + padding * 2 + 18)
		} else {
			const viewport = getViewport()
			x = snapCoordinate(viewport.x + 96)
			y = snapCoordinate(viewport.y + 96)
			width = 360
			height = 200
		}

		const block: AnnotationBlock = {
			id: nanoid(),
			label: selected.length ? "Group" : "Annotation",
			color: "#64b5f6",
			x,
			y,
			width,
			height,
		}

		annotationBlocks.value.push(block)
		selectAnnotationBlock(block.id)
		commitUndo()
	}

	function annotationBlockStyle(block: AnnotationBlock) {
		return {
			transform: `translate(${block.x}px, ${block.y}px)`,
			width: `${block.width}px`,
			height: `${block.height}px`,
			borderColor: block.color,
			background: `color-mix(in srgb, ${block.color} 12%, transparent)`,
		}
	}

	function startAnnotationBlockDrag(event: PointerEvent, block: AnnotationBlock) {
		if ((event.target as HTMLElement).closest(".node-automation__annotation-resize")) return
		event.preventDefault()
		selectAnnotationBlock(block.id)

		const startX = event.clientX
		const startY = event.clientY
		const originalX = block.x
		const originalY = block.y
		const target = event.currentTarget as HTMLElement
		target.setPointerCapture(event.pointerId)

		function onMove(moveEvent: PointerEvent) {
			const dx = (moveEvent.clientX - startX) / getZoom()
			const dy = (moveEvent.clientY - startY) / getZoom()
			block.x = snapCoordinate(originalX + dx)
			block.y = snapCoordinate(originalY + dy)
		}

		function onUp(upEvent: PointerEvent) {
			target.releasePointerCapture(upEvent.pointerId)
			target.removeEventListener("pointermove", onMove)
			target.removeEventListener("pointerup", onUp)
			target.removeEventListener("pointercancel", onUp)
			commitUndo()
		}

		target.addEventListener("pointermove", onMove)
		target.addEventListener("pointerup", onUp)
		target.addEventListener("pointercancel", onUp)
	}

	function startAnnotationBlockResize(event: PointerEvent, block: AnnotationBlock) {
		event.preventDefault()
		selectAnnotationBlock(block.id)

		const startX = event.clientX
		const startY = event.clientY
		const startWidth = block.width
		const startHeight = block.height
		const target = event.currentTarget as HTMLElement
		target.setPointerCapture(event.pointerId)

		function onMove(moveEvent: PointerEvent) {
			const dx = (moveEvent.clientX - startX) / getZoom()
			const dy = (moveEvent.clientY - startY) / getZoom()
			block.width = Math.max(160, Math.round(startWidth + dx))
			block.height = Math.max(96, Math.round(startHeight + dy))
		}

		function onUp(upEvent: PointerEvent) {
			target.releasePointerCapture(upEvent.pointerId)
			target.removeEventListener("pointermove", onMove)
			target.removeEventListener("pointerup", onUp)
			target.removeEventListener("pointercancel", onUp)
			commitUndo()
		}

		target.addEventListener("pointermove", onMove)
		target.addEventListener("pointerup", onUp)
		target.addEventListener("pointercancel", onUp)
	}

	function updateSelectedAnnotationBlockLabel(label: string) {
		if (!selectedAnnotationBlock.value) return
		selectedAnnotationBlock.value.label = label.trim() || "Annotation"
		commitUndo()
	}

	function updateSelectedAnnotationBlockColor(color: string) {
		if (!selectedAnnotationBlock.value) return
		selectedAnnotationBlock.value.color = color || "#64b5f6"
		commitUndo()
	}

	function deleteSelectedAnnotationBlock() {
		const id = selectedAnnotationBlockId.value
		if (!id) return
		const index = annotationBlocks.value.findIndex((block) => block.id === id)
		if (index >= 0) annotationBlocks.value.splice(index, 1)
		selectedAnnotationBlockId.value = undefined
		commitUndo()
	}

	return {
		annotationBlocks,
		selectedAnnotationBlock,
		addAnnotationBlock,
		annotationBlockStyle,
		startAnnotationBlockDrag,
		startAnnotationBlockResize,
		updateSelectedAnnotationBlockLabel,
		updateSelectedAnnotationBlockColor,
		deleteSelectedAnnotationBlock,
	}
}
