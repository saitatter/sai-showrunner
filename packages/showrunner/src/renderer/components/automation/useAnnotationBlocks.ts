import { computed, type Ref } from "vue"
import { nanoid } from "nanoid"
import type { NodePosition } from "./useNodeCanvas"

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
	selectedAnnotationBlockId: Ref<string | undefined>
	getZoom: () => number
	snapCoordinate: (value: number) => number
	getViewport: () => { x: number; y: number }
	selectAnnotationBlock: (blockId: string) => void
	commitUndo: () => void
}

export function useAnnotationBlocks({
	view,
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

	function addAnnotationBlock(position?: NodePosition) {
		const viewport = getViewport()
		const x = snapCoordinate(position?.x ?? viewport.x + 96)
		const y = snapCoordinate(position?.y ?? viewport.y + 96)

		const block: AnnotationBlock = {
			id: nanoid(),
			label: "Annotation",
			color: "#64b5f6",
			x,
			y,
			width: 360,
			height: 200,
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
