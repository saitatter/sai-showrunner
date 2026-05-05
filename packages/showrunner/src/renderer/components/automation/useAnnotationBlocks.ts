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
	nodeIds?: string[]
}

interface AnnotationBlockView {
	annotationBlocks?: AnnotationBlock[]
}

interface UseAnnotationBlocksOptions {
	view: Ref<AnnotationBlockView>
	nodes: ComputedRef<NodeData[]>
	selectedAnnotationBlockId: Ref<string | undefined>
	selectedNodeIds: Ref<Set<string>>
	nodePositions: ComputedRef<Record<string, NodePosition>>
	getZoom: () => number
	snapCoordinate: (value: number) => number
	getViewport: () => { x: number; y: number }
	selectAnnotationBlock: (blockId: string) => void
	commitUndo: () => void
}

export function useAnnotationBlocks({
	view,
	nodes,
	selectedAnnotationBlockId,
	selectedNodeIds,
	nodePositions,
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
	const selectedAnnotationBlockNodeCount = computed(() => selectedAnnotationBlock.value ? getAnnotationBlockMemberCount(selectedAnnotationBlock.value) : 0)

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

	function getAnnotationBlockMemberCount(block: AnnotationBlock) {
		return getExistingNodeIds(block.nodeIds ?? []).length
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
			const nextX = snapCoordinate(originalX + dx)
			const nextY = snapCoordinate(originalY + dy)
			const offsetX = nextX - block.x
			const offsetY = nextY - block.y
			block.x = nextX
			block.y = nextY
		for (const nodeId of block.nodeIds ?? []) {
			if (!nodes.value.some((node) => node.id === nodeId)) continue
			const position = nodePositions.value[nodeId] ?? nodes.value.find((node) => node.id === nodeId)
			if (!position) continue
				nodePositions.value[nodeId] = {
					x: Math.max(12, position.x + offsetX),
					y: Math.max(12, position.y + offsetY),
				}
			}
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

	function addSelectionToSelectedAnnotationBlock() {
		if (!selectedAnnotationBlock.value) return
		addNodesToAnnotationBlock(selectedAnnotationBlock.value.id, selectedNodeIds.value)
		commitUndo()
	}

	function addNodesToAnnotationBlock(blockId: string, nodeIds: Iterable<string>) {
		const block = annotationBlocks.value.find((item) => item.id === blockId)
		if (!block) return false
		const next = new Set(block.nodeIds ?? [])
		for (const nodeId of nodeIds) next.add(nodeId)
		block.nodeIds = [...next]
		return true
	}

	function clearSelectedAnnotationBlockNodes() {
		if (!selectedAnnotationBlock.value) return
		selectedAnnotationBlock.value.nodeIds = []
		commitUndo()
	}

	function removeSelectionFromSelectedAnnotationBlock() {
		if (!selectedAnnotationBlock.value) return
		const selected = selectedNodeIds.value
		selectedAnnotationBlock.value.nodeIds = (selectedAnnotationBlock.value.nodeIds ?? []).filter((nodeId) => !selected.has(nodeId))
		commitUndo()
	}

	function getAnnotationBlockForNodes(nodeIds: Iterable<string>) {
		const bounds = getNodeBounds(nodeIds)
		if (!bounds) return undefined
		const centerX = bounds.x + bounds.width / 2
		const centerY = bounds.y + bounds.height / 2
		return annotationBlocks.value.find((block) =>
			centerX >= block.x &&
			centerX <= block.x + block.width &&
			centerY >= block.y &&
			centerY <= block.y + block.height
		)
	}

	function getNodeBounds(nodeIds: Iterable<string>) {
		const boxes = [...nodeIds].map((nodeId) => {
			const node = nodes.value.find((item) => item.id === nodeId)
			if (!node) return undefined
			const position = nodePositions.value[nodeId] ?? node
			return {
				x: position.x,
				y: position.y,
				width: node.width ?? 220,
				height: node.height,
			}
		}).filter((box): box is { x: number; y: number; width: number; height: number } => Boolean(box))
		if (!boxes.length) return undefined
		const minX = Math.min(...boxes.map((box) => box.x))
		const minY = Math.min(...boxes.map((box) => box.y))
		const maxX = Math.max(...boxes.map((box) => box.x + box.width))
		const maxY = Math.max(...boxes.map((box) => box.y + box.height))
		return { x: minX, y: minY, width: maxX - minX, height: maxY - minY }
	}

	function getExistingNodeIds(nodeIds: Iterable<string>) {
		const existing = new Set(nodes.value.map((node) => node.id))
		return [...nodeIds].filter((nodeId) => existing.has(nodeId))
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
		selectedAnnotationBlockNodeCount,
		addAnnotationBlock,
		annotationBlockStyle,
		getAnnotationBlockMemberCount,
		startAnnotationBlockDrag,
		startAnnotationBlockResize,
		updateSelectedAnnotationBlockLabel,
		updateSelectedAnnotationBlockColor,
		addSelectionToSelectedAnnotationBlock,
		addNodesToAnnotationBlock,
		clearSelectedAnnotationBlockNodes,
		removeSelectionFromSelectedAnnotationBlock,
		getAnnotationBlockForNodes,
		deleteSelectedAnnotationBlock,
	}
}
