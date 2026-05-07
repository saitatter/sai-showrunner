import { describe, expect, it } from "vitest"
import { computed, ref } from "vue"
import { useAnnotationBlocks, type AnnotationBlock } from "./useAnnotationBlocks"

function createAnnotationBlocks() {
	const view = ref<{ annotationBlocks?: AnnotationBlock[] }>({})
	const selectedAnnotationBlockId = ref<string>()
	const selectedNodeIds = ref(new Set<string>())
	const nodes = ref([
		{ id: "node-a", x: 120, y: 130, height: 80, width: 220 },
		{ id: "node-b", x: 180, y: 170, height: 80, width: 220 },
	])
	const nodePositions = ref({} as Record<string, { x: number; y: number }>)
	let commitCount = 0
	const blocks = useAnnotationBlocks({
		view,
		nodes: computed(() => nodes.value),
		selectedAnnotationBlockId,
		selectedNodeIds,
		nodePositions,
		getZoom: () => 1,
		snapCoordinate: (value) => Math.round(value / 10) * 10,
		getViewport: () => ({ x: 100, y: 200 }),
		selectAnnotationBlock: (blockId) => {
			selectedAnnotationBlockId.value = blockId
		},
		commitUndo: () => {
			commitCount += 1
		},
	})
	return { blocks, view, nodes, selectedAnnotationBlockId, selectedNodeIds, getCommitCount: () => commitCount }
}

describe("useAnnotationBlocks", () => {
	it("creates manual annotation blocks from the visible viewport", () => {
		const { blocks, view, selectedAnnotationBlockId, getCommitCount } = createAnnotationBlocks()

		blocks.addAnnotationBlock()

		expect(view.value.annotationBlocks).toHaveLength(1)
		expect(view.value.annotationBlocks?.[0]).toMatchObject({
			label: "Annotation",
			color: "#64b5f6",
			x: 200,
			y: 300,
			width: 360,
			height: 200,
		})
		expect(selectedAnnotationBlockId.value).toBe(view.value.annotationBlocks?.[0].id)
		expect(getCommitCount()).toBe(1)
	})

	it("creates manual annotation blocks at an explicit canvas point", () => {
		const { blocks, view } = createAnnotationBlocks()

		blocks.addAnnotationBlock({ x: 343, y: 187 })

		expect(view.value.annotationBlocks?.[0]).toMatchObject({
			label: "Annotation",
			x: 340,
			y: 190,
			width: 360,
			height: 200,
		})
	})

	it("creates annotation blocks around the current node selection", () => {
		const { blocks, view, nodes, selectedNodeIds } = createAnnotationBlocks()
		nodes.value[1] = { ...nodes.value[1], x: 520, y: 260 }
		selectedNodeIds.value = new Set(["node-a", "node-b"])

		blocks.addAnnotationBlock()

		expect(view.value.annotationBlocks?.[0]).toMatchObject({
			x: 80,
			y: 90,
			width: 700,
			height: 290,
			nodeIds: ["node-a", "node-b"],
		})
	})

	it("moves selected nodes out of existing blocks when creating a new block from selection", () => {
		const { blocks, view, selectedNodeIds } = createAnnotationBlocks()

		blocks.addAnnotationBlock({ x: 100, y: 100 })
		const firstBlockId = view.value.annotationBlocks![0].id
		blocks.addNodesToAnnotationBlock(firstBlockId, ["node-a", "node-b"])
		selectedNodeIds.value = new Set(["node-a"])

		blocks.addAnnotationBlock()

		expect(view.value.annotationBlocks![0].nodeIds).toEqual(["node-b"])
		expect(view.value.annotationBlocks![1].nodeIds).toEqual(["node-a"])
	})

	it("adds the current node selection to the selected annotation block", () => {
		const { blocks, view, selectedNodeIds } = createAnnotationBlocks()

		blocks.addAnnotationBlock()
		selectedNodeIds.value = new Set(["node-a", "node-b"])
		blocks.addSelectionToSelectedAnnotationBlock()

		expect(view.value.annotationBlocks?.[0].nodeIds).toEqual(["node-a", "node-b"])
	})

	it("clears member nodes from the selected annotation block", () => {
		const { blocks, view, selectedNodeIds } = createAnnotationBlocks()

		blocks.addAnnotationBlock()
		selectedNodeIds.value = new Set(["node-a"])
		blocks.addSelectionToSelectedAnnotationBlock()
		blocks.clearSelectedAnnotationBlockNodes()

		expect(view.value.annotationBlocks?.[0].nodeIds).toEqual([])
	})

	it("removes only the current node selection from the selected annotation block", () => {
		const { blocks, view, selectedNodeIds } = createAnnotationBlocks()

		blocks.addAnnotationBlock()
		selectedNodeIds.value = new Set(["node-a", "node-b", "node-c"])
		blocks.addSelectionToSelectedAnnotationBlock()
		selectedNodeIds.value = new Set(["node-b"])
		blocks.removeSelectionFromSelectedAnnotationBlock()

		expect(view.value.annotationBlocks?.[0].nodeIds).toEqual(["node-a", "node-c"])
	})

	it("finds a block containing the dragged node selection center", () => {
		const { blocks, view } = createAnnotationBlocks()

		blocks.addAnnotationBlock({ x: 100, y: 100 })

		expect(blocks.getAnnotationBlockForNodes(new Set(["node-a", "node-b"]))?.id).toBe(view.value.annotationBlocks?.[0].id)
	})

	it("adds dragged nodes to a block without duplicating existing members", () => {
		const { blocks, view } = createAnnotationBlocks()

		blocks.addAnnotationBlock()
		const blockId = view.value.annotationBlocks?.[0].id
		expect(blockId).toBeTruthy()
		blocks.addNodesToAnnotationBlock(blockId!, ["node-a"])
		blocks.addNodesToAnnotationBlock(blockId!, ["node-a", "node-b"])

		expect(view.value.annotationBlocks?.[0].nodeIds).toEqual(["node-a", "node-b"])
	})

	it("finds annotation blocks that currently contain dragged nodes", () => {
		const { blocks, view } = createAnnotationBlocks()

		blocks.addAnnotationBlock({ x: 100, y: 100 })
		const firstBlockId = view.value.annotationBlocks![0].id
		blocks.addAnnotationBlock({ x: 500, y: 100 })
		const secondBlockId = view.value.annotationBlocks![1].id
		blocks.addNodesToAnnotationBlock(firstBlockId, ["node-a"])
		blocks.addNodesToAnnotationBlock(secondBlockId, ["node-b"])

		expect(blocks.getAnnotationBlockIdsForNodes(["node-a", "node-b"])).toEqual([firstBlockId, secondBlockId])
	})

	it("counts only existing member nodes for legacy or stale block data", () => {
		const { blocks, view } = createAnnotationBlocks()

		blocks.addAnnotationBlock()
		view.value.annotationBlocks![0].nodeIds = ["node-a", "missing-node"]

		expect(blocks.getAnnotationBlockMemberCount(view.value.annotationBlocks![0])).toBe(1)
	})

	it("moves dragged nodes from one annotation block to another", () => {
		const { blocks, view } = createAnnotationBlocks()

		blocks.addAnnotationBlock({ x: 100, y: 100 })
		const firstBlockId = view.value.annotationBlocks![0].id
		blocks.addAnnotationBlock({ x: 500, y: 100 })
		const secondBlockId = view.value.annotationBlocks![1].id
		blocks.addNodesToAnnotationBlock(firstBlockId, ["node-a"])

		expect(blocks.placeDraggedNodesInAnnotationBlock(secondBlockId, ["node-a"])).toBe(true)
		expect(view.value.annotationBlocks![0].nodeIds).toEqual([])
		expect(view.value.annotationBlocks![1].nodeIds).toEqual(["node-a"])
	})

	it("removes dragged nodes from annotation blocks when dropped outside any block", () => {
		const { blocks, view } = createAnnotationBlocks()

		blocks.addAnnotationBlock()
		const blockId = view.value.annotationBlocks![0].id
		blocks.addNodesToAnnotationBlock(blockId, ["node-a", "node-b"])

		expect(blocks.placeDraggedNodesInAnnotationBlock(undefined, ["node-a"])).toBe(true)
		expect(view.value.annotationBlocks![0].nodeIds).toEqual(["node-b"])
	})

	it("keeps resized annotation blocks large enough to contain member nodes", () => {
		const { blocks, view, nodes, selectedNodeIds } = createAnnotationBlocks()
		nodes.value[1] = { ...nodes.value[1], x: 520, y: 260 }
		selectedNodeIds.value = new Set(["node-a", "node-b"])
		blocks.addAnnotationBlock()
		const block = view.value.annotationBlocks![0]
		const listeners = new Map<string, (event: any) => void>()
		const target = {
			setPointerCapture: () => undefined,
			releasePointerCapture: () => undefined,
			addEventListener: (name: string, listener: (event: any) => void) => listeners.set(name, listener),
			removeEventListener: (name: string) => listeners.delete(name),
		}

		blocks.startAnnotationBlockResize({
			clientX: 0,
			clientY: 0,
			pointerId: 1,
			currentTarget: target,
			preventDefault: () => undefined,
		} as any, block)
		listeners.get("pointermove")?.({ clientX: -1000, clientY: -1000 })

		expect(block).toMatchObject({
			width: 700,
			height: 290,
		})
	})

	it("snaps resized annotation blocks to the graph grid", () => {
		const { blocks, view } = createAnnotationBlocks()
		blocks.addAnnotationBlock({ x: 100, y: 100 })
		const block = view.value.annotationBlocks![0]
		const listeners = new Map<string, (event: any) => void>()
		const target = {
			setPointerCapture: () => undefined,
			releasePointerCapture: () => undefined,
			addEventListener: (name: string, listener: (event: any) => void) => listeners.set(name, listener),
			removeEventListener: (name: string) => listeners.delete(name),
		}

		blocks.startAnnotationBlockResize({
			clientX: 0,
			clientY: 0,
			pointerId: 1,
			currentTarget: target,
			preventDefault: () => undefined,
		} as any, block)
		listeners.get("pointermove")?.({ clientX: 13, clientY: 17 })

		expect(block.width).toBe(370)
		expect(block.height).toBe(220)
	})
})
