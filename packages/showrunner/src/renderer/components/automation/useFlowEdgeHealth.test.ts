import { describe, expect, it } from "vitest"
import { getInvalidFlowEdgeIssues } from "./useFlowEdgeHealth"

describe("flow edge health", () => {
	const nodes = [
		{ id: "trigger", kind: "trigger", title: "Trigger" },
		{ id: "action-1", kind: "action", title: "Action" },
		{ id: "convert-1", kind: "conversion", title: "Convert String To Number" },
		{ id: "return-1", kind: "return", title: "Return" },
	] as const

	it("rejects sequence edges attached to conversion nodes", () => {
		expect(getInvalidFlowEdgeIssues([{ id: "action:convert", from: "action-1", to: "convert-1" }], [...nodes])).toEqual([
			{
				id: "action:convert",
				from: "action-1",
				to: "convert-1",
				message: "Conversion nodes are data-only: Action -> Convert String To Number",
			},
		])
	})

	it("rejects outgoing sequence edges from terminal nodes", () => {
		expect(getInvalidFlowEdgeIssues([{ id: "return:action", from: "return-1", to: "action-1" }], [...nodes])).toEqual([
			{
				id: "return:action",
				from: "return-1",
				to: "action-1",
				message: "Return is terminal and cannot continue sequence flow.",
			},
		])
	})

	it("reports missing sequence endpoints", () => {
		expect(getInvalidFlowEdgeIssues([{ id: "missing:action", from: "missing", to: "action-1" }], [...nodes])).toEqual([
			{
				id: "missing:action",
				from: "missing",
				to: "action-1",
				message: "Sequence edge starts at missing node: missing",
			},
		])
	})
})
