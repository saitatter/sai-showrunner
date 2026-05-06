import { ref, watch, type ComputedRef, type Ref } from "vue"
import {
	clampGraphZoom,
	graphFitZoom,
	graphScrollTargetForBounds,
} from "../../../../../../libs/showrunner-ui-core/src/util/graph"

export interface NodePosition {
	x: number
	y: number
}

export interface NodeEditorViewState {
	zoom?: number
	pan?: NodePosition
	snapToGrid?: boolean
}

interface NodeEditorView {
	nodeView?: NodeEditorViewState
}

interface GraphBounds {
	minX: number
	minY: number
	width: number
	height: number
}

const GRID_SIZE = 42
const MIN_ZOOM = 0.35
const MAX_ZOOM = 1.5
export const ZOOM_STEP = 0.1

export function useNodeCanvas(view: Ref<NodeEditorView>, graphBounds: ComputedRef<GraphBounds>, commitUndo: () => void) {
	const canvasRef = ref<HTMLElement>()
	const nodeView = view.value?.nodeView
	const zoom = ref(nodeView?.zoom ?? 1)
	const pan = ref(nodeView?.pan ?? { x: 0, y: 0 })
	const isPanning = ref(false)
	const snapToGrid = ref(nodeView?.snapToGrid ?? true)

	watch(
		[zoom, pan, snapToGrid],
		() => {
			if (!view.value) return
			view.value.nodeView = {
				zoom: zoom.value,
				pan: pan.value,
				snapToGrid: snapToGrid.value,
			}
		},
		{ deep: true, immediate: true }
	)

	function setZoom(nextZoom: number, commitChange = false) {
		const previous = zoom.value
		zoom.value = clampGraphZoom(nextZoom, MIN_ZOOM, MAX_ZOOM)
		if (commitChange && previous !== zoom.value) commitUndo()
	}

	function toggleSnapToGrid() {
		snapToGrid.value = !snapToGrid.value
		commitUndo()
	}

	function snapCoordinate(value: number) {
		if (!snapToGrid.value) return value
		return Math.round(value / GRID_SIZE) * GRID_SIZE
	}

	function zoomFromWheel(event: WheelEvent) {
		const canvas = canvasRef.value
		if (!canvas) return
		const prevZoom = zoom.value
		const nextZoom = clampGraphZoom(prevZoom + (event.deltaY > 0 ? -ZOOM_STEP : ZOOM_STEP), MIN_ZOOM, MAX_ZOOM)
		if (nextZoom === prevZoom) return

		// Zoom toward cursor position
		const rect = canvas.getBoundingClientRect()
		const cursorX = event.clientX - rect.left + canvas.scrollLeft
		const cursorY = event.clientY - rect.top + canvas.scrollTop

		// Point in canvas space under cursor before zoom
		const worldX = (cursorX - pan.value.x) / prevZoom
		const worldY = (cursorY - pan.value.y) / prevZoom

		zoom.value = nextZoom

		// After zoom, adjust scroll so the same world point stays under the cursor
		const newScrollX = worldX * nextZoom + pan.value.x - (event.clientX - rect.left)
		const newScrollY = worldY * nextZoom + pan.value.y - (event.clientY - rect.top)
		canvas.scrollTo({ left: Math.max(0, newScrollX), top: Math.max(0, newScrollY) })
	}

	function fitGraph() {
		const canvas = canvasRef.value
		if (!canvas) return
		const bounds = graphBounds.value
		setZoom(graphFitZoom(bounds, { width: canvas.clientWidth, height: canvas.clientHeight }, { padding: 56, maxZoom: 1, minZoom: MIN_ZOOM }))
		pan.value = { x: 0, y: 0 }
		const target = graphScrollTargetForBounds(bounds, zoom.value, 28)
		canvas.scrollTo({
			left: target.x,
			top: target.y,
			behavior: "smooth",
		})
		commitUndo()
	}

	function resetView() {
		zoom.value = 1
		pan.value = { x: 0, y: 0 }
		canvasRef.value?.scrollTo({ left: 0, top: 0, behavior: "smooth" })
		commitUndo()
	}

	function fitSelection(bounds: { minX: number; minY: number; width: number; height: number }) {
		const canvas = canvasRef.value
		if (!canvas) return
		setZoom(graphFitZoom(bounds, { width: canvas.clientWidth, height: canvas.clientHeight }, { padding: 56, maxZoom: 1, minZoom: MIN_ZOOM }))
		pan.value = { x: 0, y: 0 }
		const target = graphScrollTargetForBounds(bounds, zoom.value, 28)
		canvas.scrollTo({
			left: target.x,
			top: target.y,
			behavior: "smooth",
		})
		commitUndo()
	}

	function startPan(event: PointerEvent) {
		const canvas = canvasRef.value
		if (!canvas) return

		isPanning.value = true
		const startX = event.clientX
		const startY = event.clientY
		const initialPan = { ...pan.value }
		canvas.setPointerCapture(event.pointerId)

		function onMove(moveEvent: PointerEvent) {
			pan.value = {
				x: initialPan.x + moveEvent.clientX - startX,
				y: initialPan.y + moveEvent.clientY - startY,
			}
		}

		function onUp(upEvent: PointerEvent) {
			const moved = initialPan.x !== pan.value.x || initialPan.y !== pan.value.y
			isPanning.value = false
			canvas?.releasePointerCapture(upEvent.pointerId)
			canvas?.removeEventListener("pointermove", onMove)
			canvas?.removeEventListener("pointerup", onUp)
			canvas?.removeEventListener("pointercancel", onUp)
			if (moved) commitUndo()
		}

		canvas.addEventListener("pointermove", onMove)
		canvas.addEventListener("pointerup", onUp)
		canvas.addEventListener("pointercancel", onUp)
	}

	function getCanvasPointFromClient(clientX: number, clientY: number): NodePosition {
		const surface = canvasRef.value?.querySelector<HTMLElement>(".node-automation__surface")
		const rect = surface?.getBoundingClientRect()
		if (!rect) return { x: 42, y: 88 }
		return {
			x: snapCoordinate(Math.max(12, (clientX - rect.left) / zoom.value)),
			y: snapCoordinate(Math.max(12, (clientY - rect.top) / zoom.value)),
		}
	}

	function horizontalPan(event: WheelEvent) {
		const canvas = canvasRef.value
		if (!canvas) return
		canvas.scrollBy({ left: event.deltaY })
	}

	return {
		canvasRef,
		zoom,
		pan,
		isPanning,
		snapToGrid,
		ZOOM_STEP,
		setZoom,
		toggleSnapToGrid,
		snapCoordinate,
		zoomFromWheel,
		horizontalPan,
		fitGraph,
		resetView,
		fitSelection,
		startPan,
		getCanvasPointFromClient,
	}
}
