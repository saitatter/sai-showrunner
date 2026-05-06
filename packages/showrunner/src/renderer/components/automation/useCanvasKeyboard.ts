import { nextTick, watch, type ComputedRef, type Ref } from "vue"
import type { AutomationGraph } from "showrunner-schema"
import type { NodePosition } from "./useNodeCanvas"
import { NODE_WIDTH, type NodeData } from "./useNodeRendering"

interface CanvasSearchOverlay {
	focusSearchInput: () => void
}

interface UseCanvasKeyboardOptions {
	nodes: ComputedRef<NodeData[]>
	selectedNode: ComputedRef<NodeData | undefined>
	selectedNodeId: Ref<string | undefined>
	selectedNodeIds: Ref<Set<string>>
	selectedEdgeId: Ref<string | undefined>
	selectedDataWireId: Ref<string | undefined>
	activeGraph: ComputedRef<AutomationGraph | undefined>
	canEditSelectedAction: ComputedRef<boolean>
	spaceHeld: Ref<boolean>
	canvasRef: Ref<HTMLElement | undefined>
	canvasSearchOpen: Ref<boolean>
	canvasSearchQuery: Ref<string>
	canvasSearchIndex: Ref<number>
	canvasSearchResults: ComputedRef<NodeData[]>
	canvasOverlaysRef: Ref<CanvasSearchOverlay | undefined>
	nodePositions: ComputedRef<Record<string, NodePosition>>
	zoom: Ref<number>
	pan: Ref<NodePosition>
	zoomStep: number
	contextMenuOpen: () => boolean
	closeContextMenu: () => void
	focusNode: (nodeId: string) => void
	deleteSelectedAction: () => void
	deleteVariableNode: (nodeId: string) => void
	deleteSelectedEdge: () => void
	animateWireRemoval: (wireId: string) => void
	duplicateSelectedAction: () => void
	copySelectedNodes: () => void
	cutSelectedNodes: () => void
	pasteNodes: () => void
	setZoom: (zoom: number, commitChange?: boolean) => void
	resetView: () => void
	fitGraph: () => void
}

export function useCanvasKeyboard(options: UseCanvasKeyboardOptions) {
	const {
		nodes,
		selectedNode,
		selectedNodeId,
		selectedNodeIds,
		selectedEdgeId,
		selectedDataWireId,
		activeGraph,
		canEditSelectedAction,
		spaceHeld,
		canvasRef,
		canvasSearchOpen,
		canvasSearchQuery,
		canvasSearchIndex,
		canvasSearchResults,
		canvasOverlaysRef,
		nodePositions,
		zoom,
		pan,
		zoomStep,
		contextMenuOpen,
		closeContextMenu,
		focusNode,
		deleteSelectedAction,
		deleteVariableNode,
		deleteSelectedEdge,
		animateWireRemoval,
		duplicateSelectedAction,
		copySelectedNodes,
		cutSelectedNodes,
		pasteNodes,
		setZoom,
		resetView,
		fitGraph,
	} = options

	function handleKeydown(event: KeyboardEvent) {
		const target = event.target as HTMLElement | null
		if (target?.closest("input, textarea, select, [contenteditable='true']")) return

		if (event.code === "Space" && !event.ctrlKey && !event.metaKey) {
			spaceHeld.value = true
		}

		if (event.key === "Escape" && contextMenuOpen()) {
			event.preventDefault()
			closeContextMenu()
			return
		}

		if (event.key === "Delete" || event.key === "Backspace") {
			const hasDeletableNodes = [...selectedNodeIds.value].some((id) => id !== "trigger")
			const hasSelectedExplicitTrigger = selectedNode.value?.kind === "trigger" && selectedNode.value.id !== "trigger"
			if (canEditSelectedAction.value || hasDeletableNodes || hasSelectedExplicitTrigger) {
				event.preventDefault()
				deleteSelectedAction()
			} else if (selectedNode.value?.kind === "variable") {
				event.preventDefault()
				deleteVariableNode(selectedNode.value.id)
				selectedNodeId.value = undefined
				selectedNodeIds.value = new Set()
			} else if (selectedEdgeId.value) {
				event.preventDefault()
				deleteSelectedEdge()
			} else if (selectedDataWireId.value) {
				event.preventDefault()
				animateWireRemoval(selectedDataWireId.value)
				selectedDataWireId.value = undefined
			}
		}

		if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "d" && canEditSelectedAction.value) {
			event.preventDefault()
			duplicateSelectedAction()
		}

		if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "c") {
			event.preventDefault()
			copySelectedNodes()
		}

		if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "x") {
			event.preventDefault()
			cutSelectedNodes()
		}

		if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "v") {
			event.preventDefault()
			pasteNodes()
		}

		if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "a") {
			event.preventDefault()
			selectedNodeIds.value = new Set(nodes.value.map((n) => n.id))
			selectedNodeId.value = nodes.value[0]?.id
		}

		if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "f") {
			event.preventDefault()
			openCanvasSearch()
		}

		if (["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"].includes(event.key) && !event.ctrlKey && !event.metaKey) {
			event.preventDefault()
			navigateToAdjacentNode(event.key as "ArrowLeft" | "ArrowRight" | "ArrowUp" | "ArrowDown", event.shiftKey)
		}

		if ((event.ctrlKey || event.metaKey) && (event.key === "=" || event.key === "+")) {
			event.preventDefault()
			setZoom(zoom.value + zoomStep, true)
		}
		if ((event.ctrlKey || event.metaKey) && event.key === "-") {
			event.preventDefault()
			setZoom(zoom.value - zoomStep, true)
		}
		if ((event.ctrlKey || event.metaKey) && event.key === "0") {
			event.preventDefault()
			resetView()
		}

		if (event.key.toLowerCase() === "f" && !event.ctrlKey && !event.metaKey) {
			event.preventDefault()
			fitGraph()
		}
	}

	function handleKeyup(event: KeyboardEvent) {
		if (event.code === "Space") {
			spaceHeld.value = false
		}
	}

	function navigateToAdjacentNode(direction: "ArrowLeft" | "ArrowRight" | "ArrowUp" | "ArrowDown", extend: boolean) {
		const current = selectedNode.value ?? nodes.value[0]
		if (!current) return

		const cx = current.x + (current.width ?? NODE_WIDTH) / 2
		const cy = current.y + current.height / 2
		const candidates = nodes.value.filter((n) => n.id !== current.id)

		let best: NodeData | undefined
		let bestScore = Infinity

		for (const node of candidates) {
			const nx = node.x + (node.width ?? NODE_WIDTH) / 2
			const ny = node.y + node.height / 2
			const dx = nx - cx
			const dy = ny - cy

			let inDirection = false
			let primaryDist = 0
			let crossDist = 0

			switch (direction) {
				case "ArrowRight":
					inDirection = dx > 20
					primaryDist = dx
					crossDist = Math.abs(dy)
					break
				case "ArrowLeft":
					inDirection = dx < -20
					primaryDist = -dx
					crossDist = Math.abs(dy)
					break
				case "ArrowDown":
					inDirection = dy > 20
					primaryDist = dy
					crossDist = Math.abs(dx)
					break
				case "ArrowUp":
					inDirection = dy < -20
					primaryDist = -dy
					crossDist = Math.abs(dx)
					break
			}

			if (!inDirection) continue
			const score = primaryDist + crossDist * 2
			if (score < bestScore) {
				bestScore = score
				best = node
			}
		}

		if (!best) return

		if (extend) {
			const next = new Set(selectedNodeIds.value)
			next.add(best.id)
			selectedNodeIds.value = next
			selectedNodeId.value = best.id
			return
		}
		focusNode(best.id)
	}

	function openCanvasSearch() {
		canvasSearchOpen.value = true
		canvasSearchQuery.value = ""
		canvasSearchIndex.value = 0
		nextTick(() => canvasOverlaysRef.value?.focusSearchInput())
	}

	function closeCanvasSearch() {
		canvasSearchOpen.value = false
		canvasSearchQuery.value = ""
		canvasSearchIndex.value = 0
	}

	function cycleSearchResult(direction: 1 | -1) {
		const results = canvasSearchResults.value
		if (!results.length) return
		canvasSearchIndex.value = (canvasSearchIndex.value + direction + results.length) % results.length
		const node = results[canvasSearchIndex.value]
		focusNode(node.id)
		scrollToNode(node)
	}

	function scrollToNode(node: NodeData) {
		const canvas = canvasRef.value
		if (!canvas) return
		const pos = nodePositions.value[node.id] ?? node
		const centerX = (pos.x + (node.width ?? NODE_WIDTH) / 2) * zoom.value + pan.value.x - canvas.clientWidth / 2
		const centerY = (pos.y + node.height / 2) * zoom.value + pan.value.y - canvas.clientHeight / 2
		canvas.scrollTo({ left: Math.max(0, centerX), top: Math.max(0, centerY), behavior: "smooth" })
	}

	watch(canvasSearchQuery, () => {
		canvasSearchIndex.value = 0
		if (canvasSearchResults.value.length) {
			const node = canvasSearchResults.value[0]
			focusNode(node.id)
			scrollToNode(node)
		}
	})

	return {
		handleKeydown,
		handleKeyup,
		openCanvasSearch,
		closeCanvasSearch,
		cycleSearchResult,
		scrollToNode,
	}
}
