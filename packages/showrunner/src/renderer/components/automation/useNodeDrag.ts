import { ref, type ComputedRef, type Ref } from "vue"
import type { NodePosition } from "./useNodeCanvas"

interface DraggableNode extends NodePosition {
	id: string
	height: number
}

export interface AlignmentGuide {
	axis: "x" | "y"
	position: number
	from: number
	to: number
}

const SNAP_THRESHOLD = 6

export function useNodeDrag(
	nodePositions: ComputedRef<Record<string, NodePosition>>,
	selectedNodeId: Ref<string | undefined>,
	selectedNodeIds: Ref<Set<string>>,
	zoom: Ref<number>,
	snapCoordinate: (value: number) => number,
	closeContextMenu: () => void,
	commitUndo: () => void,
	allNodes: ComputedRef<DraggableNode[]>,
	nodeWidth: number
) {
	const alignmentGuides = ref<AlignmentGuide[]>([])

	function startDrag(event: PointerEvent, node: DraggableNode) {
		closeContextMenu()

		// If dragging a non-selected node, focus it first
		if (!selectedNodeIds.value.has(node.id)) {
			selectedNodeId.value = node.id
			selectedNodeIds.value = new Set([node.id])
		}

		const startX = event.clientX
		const startY = event.clientY

		// Collect initial positions for all selected nodes
		const draggedIds = new Set(selectedNodeIds.value)
		const initialPositions = new Map<string, NodePosition>()
		for (const id of draggedIds) {
			const n = allNodes.value.find((nd) => nd.id === id)
			if (n) {
				initialPositions.set(id, nodePositions.value[id] ?? { x: n.x, y: n.y })
			}
		}

		const target = event.currentTarget as HTMLElement
		target.setPointerCapture(event.pointerId)

		function onMove(moveEvent: PointerEvent) {
			const dx = (moveEvent.clientX - startX) / zoom.value
			const dy = (moveEvent.clientY - startY) / zoom.value

			// Calculate the primary node's raw position first
			const primaryInitial = initialPositions.get(node.id) ?? { x: node.x, y: node.y }
			const rawX = snapCoordinate(Math.max(12, primaryInitial.x + dx))
			const rawY = snapCoordinate(Math.max(12, primaryInitial.y + dy))
			const primaryHeight = allNodes.value.find((n) => n.id === node.id)?.height ?? 74

			// Collect reference edges from non-dragged nodes
			const refNodes = allNodes.value.filter((n) => !draggedIds.has(n.id))
			const guides: AlignmentGuide[] = []
			let snapDx = 0
			let snapDy = 0
			let bestDistX = SNAP_THRESHOLD + 1
			let bestDistY = SNAP_THRESHOLD + 1

			const dragLeft = rawX
			const dragRight = rawX + nodeWidth
			const dragCenterX = rawX + nodeWidth / 2
			const dragTop = rawY
			const dragBottom = rawY + primaryHeight
			const dragCenterY = rawY + primaryHeight / 2

			for (const ref of refNodes) {
				const refLeft = ref.x
				const refRight = ref.x + nodeWidth
				const refCenterX = ref.x + nodeWidth / 2
				const refTop = ref.y
				const refBottom = ref.y + ref.height
				const refCenterY = ref.y + ref.height / 2

				// X-axis alignment (vertical guides)
				const xPairs: [number, number][] = [
					[dragLeft, refLeft],
					[dragLeft, refRight],
					[dragRight, refLeft],
					[dragRight, refRight],
					[dragCenterX, refCenterX],
				]
				for (const [dragEdge, refEdge] of xPairs) {
					const dist = Math.abs(dragEdge - refEdge)
					if (dist < SNAP_THRESHOLD && dist < bestDistX) {
						bestDistX = dist
						snapDx = refEdge - dragEdge
					}
				}

				// Y-axis alignment (horizontal guides)
				const yPairs: [number, number][] = [
					[dragTop, refTop],
					[dragTop, refBottom],
					[dragBottom, refTop],
					[dragBottom, refBottom],
					[dragCenterY, refCenterY],
				]
				for (const [dragEdge, refEdge] of yPairs) {
					const dist = Math.abs(dragEdge - refEdge)
					if (dist < SNAP_THRESHOLD && dist < bestDistY) {
						bestDistY = dist
						snapDy = refEdge - dragEdge
					}
				}
			}

			const finalX = rawX + snapDx
			const finalY = rawY + snapDy

			// Build guide lines for matched alignments
			for (const ref of refNodes) {
				const refLeft = ref.x
				const refRight = ref.x + nodeWidth
				const refCenterX = ref.x + nodeWidth / 2
				const refTop = ref.y
				const refBottom = ref.y + ref.height
				const refCenterY = ref.y + ref.height / 2

				if (bestDistX <= SNAP_THRESHOLD) {
					const snappedEdges = [finalX, finalX + nodeWidth, finalX + nodeWidth / 2]
					const refEdges = [refLeft, refRight, refCenterX]
					for (const se of snappedEdges) {
						for (const re of refEdges) {
							if (Math.abs(se - re) < 1) {
								const minY = Math.min(finalY, refTop)
								const maxY = Math.max(finalY + primaryHeight, refBottom)
								guides.push({ axis: "x", position: re, from: minY, to: maxY })
							}
						}
					}
				}

				if (bestDistY <= SNAP_THRESHOLD) {
					const snappedEdges = [finalY, finalY + primaryHeight, finalY + primaryHeight / 2]
					const refEdges = [refTop, refBottom, refCenterY]
					for (const se of snappedEdges) {
						for (const re of refEdges) {
							if (Math.abs(se - re) < 1) {
								const minX = Math.min(finalX, refLeft)
								const maxX = Math.max(finalX + nodeWidth, refRight)
								guides.push({ axis: "y", position: re, from: minX, to: maxX })
							}
						}
					}
				}
			}

			// Deduplicate guides
			const seen = new Set<string>()
			alignmentGuides.value = guides.filter((g) => {
				const key = `${g.axis}:${g.position}`
				if (seen.has(key)) return false
				seen.add(key)
				return true
			})

			// Apply positions to all dragged nodes
			const offsetX = finalX - primaryInitial.x
			const offsetY = finalY - primaryInitial.y
			for (const [id, initial] of initialPositions) {
				nodePositions.value[id] = {
					x: Math.max(12, initial.x + offsetX),
					y: Math.max(12, initial.y + offsetY),
				}
			}
		}

		function onUp(upEvent: PointerEvent) {
			target.releasePointerCapture(upEvent.pointerId)
			target.removeEventListener("pointermove", onMove)
			target.removeEventListener("pointerup", onUp)
			target.removeEventListener("pointercancel", onUp)
			alignmentGuides.value = []
			let moved = false
			for (const [id, initial] of initialPositions) {
				const pos = nodePositions.value[id]
				if (pos && (pos.x !== initial.x || pos.y !== initial.y)) {
					moved = true
					break
				}
			}
			if (moved) commitUndo()
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
		alignmentGuides,
	}
}
