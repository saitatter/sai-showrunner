import { describe, it, expect } from "vitest"
import {
	getActionById,
	getActionAndPathById,
	assignNewIds,
	isActionStack,
	isFlowAction,
	isTimeAction,
} from "../../types/sequence"
import {
	findActionById,
	findActionAndSequenceById,
	createInlineAutomation,
} from "../../types/automations"
import type {
	Sequence,
	InstantAction,
	TimeAction,
	ActionStack,
	FlowAction,
	FloatingSequence,
} from "../../types/sequence"
import type { AutomationData, AutomationDataWire } from "../../types/automations"

// Helpers
function makeAction(id: string): InstantAction {
	return { id, plugin: "test", action: "act", config: {} }
}

function makeStack(id: string, ...items: InstantAction[]): ActionStack {
	return { id, stack: items }
}

function makeFlow(id: string, ...subFlows: { id: string; actions: any[] }[]): FlowAction {
	return { id, plugin: "test", action: "flow", config: {}, subFlows: subFlows.map((f) => ({ ...f, config: {} })) }
}

function makeTimeAction(id: string): TimeAction {
	return { id, plugin: "test", action: "time", config: {}, offsets: [{ id: "off1", offset: 1, actions: [makeAction("nested-in-time")] }] }
}

function makeWire(from: string, fromPort: string, to: string, toPort: string): AutomationDataWire {
	return { id: `${from}:${fromPort}->${to}:${toPort}`, fromNode: from, fromPort, toNode: to, toPort }
}

describe("isActionStack / isFlowAction / isTimeAction", () => {
	it("should identify action stacks", () => {
		expect(isActionStack(makeStack("s1", makeAction("a1")))).toBe(true)
		expect(isActionStack(makeAction("a1"))).toBe(false)
	})

	it("should identify flow actions", () => {
		expect(isFlowAction(makeFlow("f1"))).toBe(true)
		expect(isFlowAction(makeAction("a1"))).toBe(false)
	})

	it("should identify time actions", () => {
		expect(isTimeAction(makeTimeAction("t1"))).toBe(true)
		expect(isTimeAction(makeAction("a1"))).toBe(false)
	})
})

describe("getActionById", () => {
	it("should find top-level action", () => {
		const seq: Sequence = { actions: [makeAction("a1"), makeAction("a2")] }
		expect(getActionById("a1", seq)?.id).toBe("a1")
		expect(getActionById("a2", seq)?.id).toBe("a2")
	})

	it("should return undefined for missing id", () => {
		const seq: Sequence = { actions: [makeAction("a1")] }
		expect(getActionById("missing", seq)).toBeUndefined()
	})

	it("should find action inside action stack", () => {
		const seq: Sequence = { actions: [makeStack("s1", makeAction("inner1"), makeAction("inner2"))] }
		expect(getActionById("inner1", seq)?.id).toBe("inner1")
		expect(getActionById("inner2", seq)?.id).toBe("inner2")
	})

	it("should find action inside flow subFlows", () => {
		const flow = makeFlow("f1", { id: "sf1", actions: [makeAction("deep1")] })
		const seq: Sequence = { actions: [flow] }
		expect(getActionById("deep1", seq)?.id).toBe("deep1")
	})

	it("should find action inside time action offsets", () => {
		const seq: Sequence = { actions: [makeTimeAction("t1")] }
		expect(getActionById("nested-in-time", seq)?.id).toBe("nested-in-time")
	})

	it("should find the stack itself by its id", () => {
		const stack = makeStack("s1", makeAction("a1"))
		const seq: Sequence = { actions: [stack] }
		// getActionById matches action.id == id on top-level, which is the stack
		expect(getActionById("s1", seq)).toBe(stack)
	})
})

describe("getActionAndPathById", () => {
	it("should return path for top-level action", () => {
		const seq: Sequence = { actions: [makeAction("a1"), makeAction("a2")] }
		const result = getActionAndPathById("a2", seq)
		expect(result?.path).toBe("actions[1]")
		expect(result?.action.id).toBe("a2")
	})

	it("should return path inside action stack", () => {
		const seq: Sequence = { actions: [makeStack("s1", makeAction("x"), makeAction("y"))] }
		const result = getActionAndPathById("y", seq)
		expect(result?.path).toBe("actions[0].stack[1]")
	})

	it("should return path inside flow subFlow", () => {
		const flow = makeFlow("f1", { id: "sf1", actions: [makeAction("z")] })
		const seq: Sequence = { actions: [flow] }
		const result = getActionAndPathById("z", seq)
		expect(result?.path).toContain("subFlows[0]")
		expect(result?.path).toContain("actions[0]")
	})

	it("should return path inside time action offset", () => {
		const seq: Sequence = { actions: [makeTimeAction("t1")] }
		const result = getActionAndPathById("nested-in-time", seq)
		expect(result?.path).toContain("offsets[0]")
	})

	it("should return undefined for missing id", () => {
		const seq: Sequence = { actions: [makeAction("a1")] }
		expect(getActionAndPathById("nope", seq)).toBeUndefined()
	})
})

describe("findActionAndSequenceById", () => {
	it("should find action in main sequence", () => {
		const automation: AutomationData = {
			sequence: { actions: [makeAction("a1")] },
			floatingSequences: [],
		}
		const result = findActionAndSequenceById("a1", automation)
		expect(result?.action.id).toBe("a1")
		expect(result?.path).toBe("sequence.actions[0]")
	})

	it("should find action in floating sequence", () => {
		const floating: FloatingSequence = { id: "fs1", x: 0, y: 0, actions: [makeAction("f1")] }
		const automation: AutomationData = {
			sequence: { actions: [] },
			floatingSequences: [floating],
		}
		const result = findActionAndSequenceById("f1", automation)
		expect(result?.action.id).toBe("f1")
		expect(result?.path).toContain("floatingSequences[0]")
	})

	it("should return undefined for missing action", () => {
		const automation: AutomationData = {
			sequence: { actions: [makeAction("a1")] },
			floatingSequences: [],
		}
		expect(findActionAndSequenceById("missing", automation)).toBeUndefined()
	})
})

describe("findActionById", () => {
	it("should find in main sequence", () => {
		const automation: AutomationData = {
			sequence: { actions: [makeAction("a1")] },
			floatingSequences: [],
		}
		expect(findActionById("a1", automation)?.id).toBe("a1")
	})

	it("should find in floating sequence", () => {
		const floating: FloatingSequence = { id: "fs1", x: 0, y: 0, actions: [makeAction("f1")] }
		const automation: AutomationData = {
			sequence: { actions: [] },
			floatingSequences: [floating],
		}
		expect(findActionById("f1", automation)?.id).toBe("f1")
	})
})

describe("assignNewIds", () => {
	it("should assign new ids to all actions", () => {
		const seq: Sequence = { actions: [makeAction("old1"), makeAction("old2")] }
		assignNewIds(seq)
		expect(seq.actions[0].id).not.toBe("old1")
		expect(seq.actions[1].id).not.toBe("old2")
	})

	it("should assign new ids inside action stacks", () => {
		const seq: Sequence = { actions: [makeStack("s1", makeAction("inner1"))] }
		assignNewIds(seq)
		const stack = seq.actions[0] as ActionStack
		expect(stack.id).not.toBe("s1")
		expect(stack.stack[0].id).not.toBe("inner1")
	})

	it("should assign new ids inside flow subFlows recursively", () => {
		const flow = makeFlow("f1", { id: "sf1", actions: [makeAction("deep1")] })
		const seq: Sequence = { actions: [flow] }
		assignNewIds(seq)
		const flowAction = seq.actions[0] as FlowAction
		expect(flowAction.id).not.toBe("f1")
		expect(flowAction.subFlows[0].id).not.toBe("sf1")
		expect((flowAction.subFlows[0].actions[0] as any).id).not.toBe("deep1")
	})

	it("should assign unique ids (no duplicates)", () => {
		const seq: Sequence = { actions: [makeAction("a"), makeAction("b"), makeAction("c")] }
		assignNewIds(seq)
		const ids = seq.actions.map((a) => a.id)
		expect(new Set(ids).size).toBe(3)
	})
})

describe("createInlineAutomation", () => {
	it("should create empty automation", () => {
		const auto = createInlineAutomation()
		expect(auto.sequence.actions).toEqual([])
		expect(auto.floatingSequences).toEqual([])
		expect(auto.queue).toBeUndefined()
	})
})

describe("wire filtering for copy (pure logic)", () => {
	it("should keep only wires where both ends are selected", () => {
		const wires: AutomationDataWire[] = [
			makeWire("a1", "out", "a2", "in"),
			makeWire("a2", "out", "a3", "in"),
			makeWire("a1", "out", "a3", "in"),
		]
		const selectedIds = new Set(["a1", "a2"])

		const filtered = wires.filter((w) => selectedIds.has(w.fromNode) && selectedIds.has(w.toNode))
		expect(filtered).toHaveLength(1)
		expect(filtered[0].fromNode).toBe("a1")
		expect(filtered[0].toNode).toBe("a2")
	})

	it("should return empty when nothing is selected", () => {
		const wires: AutomationDataWire[] = [makeWire("a1", "out", "a2", "in")]
		const selectedIds = new Set<string>()
		const filtered = wires.filter((w) => selectedIds.has(w.fromNode) && selectedIds.has(w.toNode))
		expect(filtered).toHaveLength(0)
	})

	it("should return all wires when all nodes are selected", () => {
		const wires: AutomationDataWire[] = [
			makeWire("a1", "out", "a2", "in"),
			makeWire("a2", "out", "a3", "in"),
		]
		const selectedIds = new Set(["a1", "a2", "a3"])
		const filtered = wires.filter((w) => selectedIds.has(w.fromNode) && selectedIds.has(w.toNode))
		expect(filtered).toHaveLength(2)
	})
})

describe("delete logic - wire cleanup", () => {
	it("should remove wires connected to deleted node", () => {
		const wires: AutomationDataWire[] = [
			makeWire("a1", "out", "a2", "in"),
			makeWire("a2", "out", "a3", "in"),
			makeWire("a1", "x", "a3", "y"),
		]
		const deletedId = "a2"
		const remaining = wires.filter((w) => w.fromNode !== deletedId && w.toNode !== deletedId)
		expect(remaining).toHaveLength(1)
		expect(remaining[0].fromNode).toBe("a1")
		expect(remaining[0].toNode).toBe("a3")
	})

	it("should remove wires for multiple deleted nodes", () => {
		const wires: AutomationDataWire[] = [
			makeWire("a1", "out", "a2", "in"),
			makeWire("a2", "out", "a3", "in"),
			makeWire("a3", "out", "a4", "in"),
		]
		const deletedIds = new Set(["a2", "a3"])
		const remaining = wires.filter((w) => !deletedIds.has(w.fromNode) && !deletedIds.has(w.toNode))
		expect(remaining).toHaveLength(0) // all wires touch a2 or a3
	})

	it("should keep unrelated wires", () => {
		const wires: AutomationDataWire[] = [
			makeWire("a1", "out", "a2", "in"),
			makeWire("a3", "out", "a4", "in"),
		]
		const deletedId = "a1"
		const remaining = wires.filter((w) => w.fromNode !== deletedId && w.toNode !== deletedId)
		expect(remaining).toHaveLength(1)
		expect(remaining[0].fromNode).toBe("a3")
	})
})
