import { describe, expect, it } from "vitest"
import { computed, ref } from "vue"
import { useAnnotationBlocks, type AnnotationBlock } from "./useAnnotationBlocks"

function createAnnotationBlocks() {
	const view = ref<{ annotationBlocks?: AnnotationBlock[] }>({})
	const selectedAnnotationBlockId = ref<string>()
	const selectedNodeIds = ref(new Set<string>())
	const nodePositions = computed(() => ({} as Record<string, { x: number; y: number }>))
	let commitCount = 0
	const blocks = useAnnotationBlocks({
		view,
		nodes: computed(() => []),
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
	return { blocks, view, selectedAnnotationBlockId, selectedNodeIds, getCommitCount: () => commitCount }
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
})
