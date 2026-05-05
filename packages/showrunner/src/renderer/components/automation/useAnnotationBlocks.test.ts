import { describe, expect, it } from "vitest"
import { ref } from "vue"
import { useAnnotationBlocks, type AnnotationBlock } from "./useAnnotationBlocks"

function createAnnotationBlocks() {
	const view = ref<{ annotationBlocks?: AnnotationBlock[] }>({})
	const selectedAnnotationBlockId = ref<string>()
	let commitCount = 0
	const blocks = useAnnotationBlocks({
		view,
		selectedAnnotationBlockId,
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
	return { blocks, view, selectedAnnotationBlockId, getCommitCount: () => commitCount }
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
})
