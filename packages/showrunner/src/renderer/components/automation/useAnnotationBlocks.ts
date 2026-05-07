import { computed, type ComputedRef, type Ref } from "vue"
import { nanoid } from "nanoid"
import {
	addGraphFrameMembers,
	getGraphFrameContainingPoint,
	getGraphFrameMinimumSize,
	getGraphItemBounds,
	moveGraphFrameMembers,
} from "../../../../../../libs/showrunner-ui-core/src/util/graph"
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
	nodePositions: Ref<Record<string, NodePosition>>
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
		const selectedNodeIdsInGraph = getExistingNodeIds(selectedNodeIds.value)
		const selectedBounds = getNodeBounds(selectedNodeIdsInGraph)
		const padding = 40
		const viewport = getViewport()
		const x = selectedBounds ? snapCoordinate(selectedBounds.x - padding) : snapCoordinate(position?.x ?? viewport.x + 96)
		const y = selectedBounds ? snapCoordinate(selectedBounds.y - padding) : snapCoordinate(position?.y ?? viewport.y + 96)

		const block: AnnotationBlock = {
			id: nanoid(),
			label: "Annotation",
			color: "#64b5f6",
			x,
			y,
			width: selectedBounds ? Math.max(360, Math.ceil(selectedBounds.width + padding * 2)) : 360,
			height: selectedBounds ? Math.max(200, Math.ceil(selectedBounds.height + padding * 2)) : 200,
			nodeIds: [],
		}

		annotationBlocks.value.push(block)
		if (selectedNodeIdsInGraph.length) {
			moveGraphFrameMembers(annotationBlocks.value, selectedNodeIdsInGraph, block.id)
		}
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
		const memberStartPositions = new Map<string, NodePosition>()
		for (const nodeId of block.nodeIds ?? []) {
			const position = getNodePosition(nodeId)
			if (position) memberStartPositions.set(nodeId, position)
		}
		const target = event.currentTarget as HTMLElement
		target.setPointerCapture(event.pointerId)

		function onMove(moveEvent: PointerEvent) {
			const dx = (moveEvent.clientX - startX) / getZoom()
			const dy = (moveEvent.clientY - startY) / getZoom()
			const nextX = snapCoordinate(originalX + dx)
			const nextY = snapCoordinate(originalY + dy)
			const offsetX = nextX - originalX
			const offsetY = nextY - originalY
			block.x = nextX
			block.y = nextY
			for (const [nodeId, position] of memberStartPositions) {
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
		const minimumSize = getAnnotationBlockMinimumSize(block)
		const target = event.currentTarget as HTMLElement
		target.setPointerCapture(event.pointerId)

		function onMove(moveEvent: PointerEvent) {
			const dx = (moveEvent.clientX - startX) / getZoom()
			const dy = (moveEvent.clientY - startY) / getZoom()
			block.width = Math.max(minimumSize.width, snapCoordinate(startWidth + dx))
			block.height = Math.max(minimumSize.height, snapCoordinate(startHeight + dy))
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
		const nextLabel = label.trim() || "Annotation"
		if (selectedAnnotationBlock.value.label === nextLabel) return
		selectedAnnotationBlock.value.label = nextLabel
		commitUndo()
	}

	function updateSelectedAnnotationBlockColor(color: string) {
		if (!selectedAnnotationBlock.value) return
		const nextColor = color || "#64b5f6"
		if (selectedAnnotationBlock.value.color === nextColor) return
		selectedAnnotationBlock.value.color = nextColor
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
		return addGraphFrameMembers(block, nodeIds)
	}

	function placeDraggedNodesInAnnotationBlock(blockId: string | undefined, nodeIds: Iterable<string>) {
		return moveGraphFrameMembers(annotationBlocks.value, nodeIds, blockId)
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
		return getGraphFrameContainingPoint(annotationBlocks.value, { x: centerX, y: centerY })
	}

	function getAnnotationBlockIdsForNodes(nodeIds: Iterable<string>) {
		const ids = new Set(nodeIds)
		if (!ids.size) return []
		return annotationBlocks.value
			.filter((block) => (block.nodeIds ?? []).some((nodeId) => ids.has(nodeId)))
			.map((block) => block.id)
	}

	function getAnnotationBlockMinimumSize(block: AnnotationBlock) {
		const bounds = getNodeBounds(getExistingNodeIds(block.nodeIds ?? []))
		return getGraphFrameMinimumSize(block, bounds, 40)
	}

	function getNodeBounds(nodeIds: Iterable<string>) {
		return getGraphItemBounds([...nodeIds].map((nodeId) => {
			const node = nodes.value.find((item) => item.id === nodeId)
			if (!node) return undefined
			const position = nodePositions.value[nodeId] ?? node
			return {
				x: position.x,
				y: position.y,
				width: node.width ?? 220,
				height: node.height,
			}
		}).filter((box): box is { id: string; x: number; y: number; width: number; height: number } => Boolean(box)))
	}

	function getExistingNodeIds(nodeIds: Iterable<string>) {
		const existing = new Set(nodes.value.map((node) => node.id))
		return [...nodeIds].filter((nodeId) => existing.has(nodeId))
	}

	function getNodePosition(nodeId: string): NodePosition | undefined {
		const node = nodes.value.find((item) => item.id === nodeId)
		if (!node) return undefined
		const position = nodePositions.value[nodeId] ?? node
		return { x: position.x, y: position.y }
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
		placeDraggedNodesInAnnotationBlock,
		clearSelectedAnnotationBlockNodes,
		removeSelectionFromSelectedAnnotationBlock,
		getAnnotationBlockForNodes,
		getAnnotationBlockIdsForNodes,
		deleteSelectedAnnotationBlock,
	}
}
