import { computed, ref } from "vue"
import { describe, expect, it, vi } from "vitest"
import { useCanvasKeyboard } from "./useCanvasKeyboard"
import type { NodeData } from "./useNodeRendering"

describe("useCanvasKeyboard", () => {
	it("allows deleting a selected explicit trigger with the keyboard", () => {
		const deleteSelectedAction = vi.fn()
		const selectedTrigger = computed<NodeData>(() => ({
			id: "trigger-1",
			kind: "trigger",
			title: "Trigger",
			subtitle: "",
			icon: "",
			x: 0,
			y: 0,
			height: 80,
		}))
		const keyboard = useCanvasKeyboard({
			nodes: computed(() => [selectedTrigger.value]),
			selectedNode: selectedTrigger,
			selectedNodeId: ref("trigger-1"),
			selectedNodeIds: ref(new Set(["trigger-1"])),
			selectedEdgeId: ref(),
			selectedDataWireId: ref(),
			activeGraph: computed(() => ({ nodes: [], edges: [], entryNodeId: "" })),
			canEditSelectedAction: computed(() => false),
			spaceHeld: ref(false),
			canvasRef: ref(),
			canvasSearchOpen: ref(false),
			canvasSearchQuery: ref(""),
			canvasSearchIndex: ref(0),
			canvasSearchResults: computed(() => []),
			canvasOverlaysRef: ref(),
			nodePositions: computed(() => ({})),
			zoom: ref(1),
			pan: ref({ x: 0, y: 0 }),
			zoomStep: 0.1,
			contextMenuOpen: () => false,
			closeContextMenu: vi.fn(),
			focusNode: vi.fn(),
			deleteSelectedAction,
			deleteVariableNode: vi.fn(),
			deleteSelectedEdge: vi.fn(),
			animateWireRemoval: vi.fn(),
			duplicateSelectedAction: vi.fn(),
			copySelectedNodes: vi.fn(),
			cutSelectedNodes: vi.fn(),
			pasteNodes: vi.fn(),
			setZoom: vi.fn(),
			resetView: vi.fn(),
			fitGraph: vi.fn(),
		})
		const event = {
			key: "Delete",
			target: undefined,
			preventDefault: vi.fn(),
		} as unknown as KeyboardEvent

		keyboard.handleKeydown(event)

		expect(event.preventDefault).toHaveBeenCalled()
		expect(deleteSelectedAction).toHaveBeenCalled()
	})
})
