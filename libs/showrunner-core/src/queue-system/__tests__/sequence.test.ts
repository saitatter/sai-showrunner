import { describe, it, expect, vi, beforeEach } from "vitest"

// Mock PluginManager before importing sequence
vi.mock("../../plugins/plugin-manager", () => ({
	PluginManager: {
		getInstance: vi.fn(() => ({
			getAction: vi.fn(),
		})),
	},
}))

// Mock deserializeSchema to pass-through
vi.mock("../../util/ipc-schema", () => ({
	deserializeSchema: vi.fn((_schema: any, value: any) => Promise.resolve(value)),
}))

// Mock globalLogger
vi.mock("../../logging/logging", () => ({
	globalLogger: { log: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() },
}))

// Mock reactivity (not needed in tests)
vi.mock("../../reactivity/reactivity", () => ({
	reactify: vi.fn((v: any) => v),
}))

// Mock template
vi.mock("../../templates/template", () => ({
	templateSchema: vi.fn((_schema: any, value: any, _ctx: any) => value),
}))

import { SequenceRunner } from "../sequence"
import { PluginManager } from "../../plugins/plugin-manager"
import { globalLogger } from "../../logging/logging"
import type { AutomationDataWire, AutomationVariableNode } from "ShowRunner-schema"

function makeAction(id: string, plugin = "test", action = "doSomething", config: any = {}) {
	return { id, plugin, action, config }
}

function makeWire(fromNode: string, fromPort: string, toNode: string, toPort: string): AutomationDataWire {
	return { id: `${fromNode}:${fromPort}->${toNode}:${toPort}`, fromNode, fromPort, toNode, toPort }
}

function makeVariable(id: string, name: string, value: any, type: "string" | "number" | "boolean" = "string"): AutomationVariableNode {
	return { id, name, type, value, x: 0, y: 0 }
}

function setupPluginAction(result: any) {
	const mockGetAction = vi.fn(() => ({
		type: "regular",
		configSchema: { type: Object, properties: {} },
		invoke: vi.fn(() => Promise.resolve(result)),
	}))
	;(PluginManager.getInstance as any).mockReturnValue({ getAction: mockGetAction })
	return mockGetAction
}

describe("SequenceRunner - wire validation", () => {
	beforeEach(() => {
		vi.clearAllMocks()
	})

	it("should filter out wires referencing non-existent nodes", () => {
		const sequence = { actions: [makeAction("a1"), makeAction("a2")] }
		const wires: AutomationDataWire[] = [
			makeWire("a1", "out", "a2", "in"), // valid
			makeWire("a1", "out", "missing", "in"), // invalid toNode
			makeWire("ghost", "out", "a2", "in"), // invalid fromNode
		]

		const runner = new SequenceRunner(sequence as any, { contextState: {} }, undefined, wires)
		// The runner should have filtered to only the valid wire
		// We can verify by checking globalLogger was called for invalid wires
		expect(globalLogger.warn).toHaveBeenCalledTimes(2)
		expect(globalLogger.warn).toHaveBeenCalledWith(expect.stringContaining("missing"))
		expect(globalLogger.warn).toHaveBeenCalledWith(expect.stringContaining("ghost"))
	})

	it("should keep all wires when all nodes exist", () => {
		const sequence = { actions: [makeAction("a1"), makeAction("a2")] }
		const wires: AutomationDataWire[] = [
			makeWire("a1", "out", "a2", "in"),
		]

		new SequenceRunner(sequence as any, { contextState: {} }, undefined, wires)
		expect(globalLogger.warn).not.toHaveBeenCalled()
	})

	it("should include variable node ids when validating wires", () => {
		const sequence = { actions: [makeAction("a1")] }
		const variables = [makeVariable("v1", "MyVar", 42, "number")]
		const wires: AutomationDataWire[] = [
			makeWire("v1", "value", "a1", "input"), // v1 is a variable node, should be valid
		]

		new SequenceRunner(sequence as any, { contextState: {} }, undefined, wires, variables)
		expect(globalLogger.warn).not.toHaveBeenCalled()
	})

	it("should handle empty wires array without error", () => {
		const sequence = { actions: [makeAction("a1")] }
		expect(() => new SequenceRunner(sequence as any, { contextState: {} }, undefined, [])).not.toThrow()
	})

	it("should handle undefined wires", () => {
		const sequence = { actions: [makeAction("a1")] }
		expect(() => new SequenceRunner(sequence as any, { contextState: {} })).not.toThrow()
	})

	it("should recognize action stack sub-actions as valid wire targets", () => {
		const sequence = {
			actions: [{ stack: [makeAction("s1"), makeAction("s2")] }],
		}
		const wires: AutomationDataWire[] = [makeWire("s1", "out", "s2", "in")]

		new SequenceRunner(sequence as any, { contextState: {} }, undefined, wires)
		expect(globalLogger.warn).not.toHaveBeenCalled()
	})

	it("should recognize flow action sub-flow actions as valid wire targets", () => {
		const sequence = {
			actions: [{
				id: "flow1",
				plugin: "test",
				action: "branch",
				config: {},
				subFlows: [{ id: "sf1", actions: [makeAction("inner1")] }],
			}],
		}
		const wires: AutomationDataWire[] = [makeWire("flow1", "out", "inner1", "in")]

		new SequenceRunner(sequence as any, { contextState: {} }, undefined, wires)
		expect(globalLogger.warn).not.toHaveBeenCalled()
	})
})

describe("SequenceRunner - variable node initialization", () => {
	beforeEach(() => {
		vi.clearAllMocks()
	})

	it("should populate nodeResults with variable values on construction", async () => {
		const sequence = { actions: [makeAction("a1")] }
		const variables = [
			makeVariable("v1", "Name", "hello"),
			makeVariable("v2", "Count", 5, "number"),
		]

		setupPluginAction({ greeting: "hi" })

		const runner = new SequenceRunner(sequence as any, { contextState: {} }, undefined, [], variables)
		// Variable values should be available for wire resolution
		// We'll verify by running with a wire from v1 to a1
		// But for this test, just ensure construction doesn't throw
		expect(runner).toBeDefined()
	})

	it("should resolve variable node value through wire into action config", async () => {
		const sequence = { actions: [makeAction("a1", "test", "doSomething", { message: "default" })] }
		const variables = [makeVariable("v1", "Greeting", "hello")]
		const wires: AutomationDataWire[] = [makeWire("v1", "value", "a1", "message")]

		const mockInvoke = vi.fn(() => Promise.resolve({ result: "done" }))
		;(PluginManager.getInstance as any).mockReturnValue({
			getAction: () => ({
				type: "regular",
				configSchema: { type: Object, properties: {} },
				invoke: mockInvoke,
			}),
		})

		const runner = new SequenceRunner(sequence as any, { contextState: {} }, undefined, wires, variables)
		await runner.run()

		// The invoke should have been called with the wired value overwriting config.message
		expect(mockInvoke).toHaveBeenCalledWith(
			expect.objectContaining({ message: "hello" }),
			expect.anything(),
			expect.anything()
		)
	})

	it("should propagate action result to connected variable node", async () => {
		const variables = [makeVariable("v1", "Result", "")]
		const sequence = { actions: [makeAction("a1", "test", "doSomething", {})] }
		const wires: AutomationDataWire[] = [makeWire("a1", "output", "v1", "value")]

		;(PluginManager.getInstance as any).mockReturnValue({
			getAction: () => ({
				type: "regular",
				configSchema: { type: Object, properties: {} },
				invoke: vi.fn(() => Promise.resolve({ output: "computed" })),
			}),
		})

		const runner = new SequenceRunner(sequence as any, { contextState: {} }, undefined, wires, variables)
		await runner.run()

		// Variable node should have been updated
		expect(variables[0].value).toBe("computed")
	})
})

describe("SequenceRunner - wire resolution", () => {
	beforeEach(() => {
		vi.clearAllMocks()
	})

	it("should pass config unchanged when no wires exist", async () => {
		const sequence = { actions: [makeAction("a1", "test", "act", { key: "original" })] }

		const mockInvoke = vi.fn(() => Promise.resolve({}))
		;(PluginManager.getInstance as any).mockReturnValue({
			getAction: () => ({
				type: "regular",
				configSchema: { type: Object, properties: {} },
				invoke: mockInvoke,
			}),
		})

		const runner = new SequenceRunner(sequence as any, { contextState: {} }, undefined, [])
		await runner.run()

		expect(mockInvoke).toHaveBeenCalledWith(
			expect.objectContaining({ key: "original" }),
			expect.anything(),
			expect.anything()
		)
	})

	it("should chain wire results through multiple actions", async () => {
		const sequence = {
			actions: [
				makeAction("a1", "test", "first", {}),
				makeAction("a2", "test", "second", { input: "default" }),
			],
		}
		const wires: AutomationDataWire[] = [makeWire("a1", "output", "a2", "input")]

		let callCount = 0
		const mockInvoke = vi.fn(() => {
			callCount++
			if (callCount === 1) return Promise.resolve({ output: "fromA1" })
			return Promise.resolve({})
		})
		;(PluginManager.getInstance as any).mockReturnValue({
			getAction: () => ({
				type: "regular",
				configSchema: { type: Object, properties: {} },
				invoke: mockInvoke,
			}),
		})

		const runner = new SequenceRunner(sequence as any, { contextState: {} }, undefined, wires)
		await runner.run()

		// Second action should receive wired value from first
		expect(mockInvoke).toHaveBeenCalledTimes(2)
		expect(mockInvoke.mock.calls[1][0]).toEqual(expect.objectContaining({ input: "fromA1" }))
	})

	it("should skip wire when source node has no result", async () => {
		const sequence = { actions: [makeAction("a1", "test", "act", { field: "keep" })] }
		// Wire from non-existent result (a0 never ran)
		const wires: AutomationDataWire[] = [makeWire("a0", "out", "a1", "field")]

		const mockInvoke = vi.fn(() => Promise.resolve({}))
		;(PluginManager.getInstance as any).mockReturnValue({
			getAction: () => ({
				type: "regular",
				configSchema: { type: Object, properties: {} },
				invoke: mockInvoke,
			}),
		})

		// a0 is referenced but only in wire - wire validation will filter it out
		// So let's add a0 as an action that returns undefined
		const sequenceWithA0 = {
			actions: [
				makeAction("a0", "test", "noop", {}),
				makeAction("a1", "test", "act", { field: "keep" }),
			],
		}
		let callIdx = 0
		const mockInvoke2 = vi.fn(() => {
			callIdx++
			if (callIdx === 1) return Promise.resolve(undefined) // a0 returns nothing
			return Promise.resolve({})
		})
		;(PluginManager.getInstance as any).mockReturnValue({
			getAction: () => ({
				type: "regular",
				configSchema: { type: Object, properties: {} },
				invoke: mockInvoke2,
			}),
		})

		const runner = new SequenceRunner(sequenceWithA0 as any, { contextState: {} }, undefined, [makeWire("a0", "out", "a1", "field")])
		await runner.run()

		// a1 should still have its original config since a0 had no result
		expect(mockInvoke2.mock.calls[1][0]).toEqual(expect.objectContaining({ field: "keep" }))
	})

	it("should skip wire when source port is missing from result", async () => {
		const sequence = {
			actions: [
				makeAction("a1", "test", "first", {}),
				makeAction("a2", "test", "second", { val: "original" }),
			],
		}
		const wires: AutomationDataWire[] = [makeWire("a1", "nonExistentPort", "a2", "val")]

		let idx = 0
		const mockInvoke = vi.fn(() => {
			idx++
			if (idx === 1) return Promise.resolve({ differentPort: "value" })
			return Promise.resolve({})
		})
		;(PluginManager.getInstance as any).mockReturnValue({
			getAction: () => ({
				type: "regular",
				configSchema: { type: Object, properties: {} },
				invoke: mockInvoke,
			}),
		})

		const runner = new SequenceRunner(sequence as any, { contextState: {} }, undefined, wires)
		await runner.run()

		// a2 should keep original value since the port didn't exist
		expect(mockInvoke.mock.calls[1][0]).toEqual(expect.objectContaining({ val: "original" }))
		expect(globalLogger.warn).toHaveBeenCalledWith(expect.stringContaining("nonExistentPort"))
	})

	it("should wrap primitive results so _result port works", async () => {
		const sequence = {
			actions: [
				makeAction("a1", "test", "first", {}),
				makeAction("a2", "test", "second", { data: "default" }),
			],
		}
		const wires: AutomationDataWire[] = [makeWire("a1", "_result", "a2", "data")]

		let idx = 0
		const mockInvoke = vi.fn(() => {
			idx++
			if (idx === 1) return Promise.resolve(42) // primitive
			return Promise.resolve({})
		})
		;(PluginManager.getInstance as any).mockReturnValue({
			getAction: () => ({
				type: "regular",
				configSchema: { type: Object, properties: {} },
				invoke: mockInvoke,
			}),
		})

		const runner = new SequenceRunner(sequence as any, { contextState: {} }, undefined, wires)
		await runner.run()

		expect(mockInvoke.mock.calls[1][0]).toEqual(expect.objectContaining({ data: 42 }))
	})
})

describe("SequenceRunner - abort", () => {
	beforeEach(() => {
		vi.clearAllMocks()
	})

	it("should abort mid-sequence", async () => {
		const sequence = {
			actions: [
				makeAction("a1", "test", "first", {}),
				makeAction("a2", "test", "second", {}),
			],
		}

		let callCount = 0
		const mockInvoke = vi.fn(async () => {
			callCount++
			return {}
		})
		;(PluginManager.getInstance as any).mockReturnValue({
			getAction: () => ({
				type: "regular",
				configSchema: { type: Object, properties: {} },
				invoke: mockInvoke,
			}),
		})

		const runner = new SequenceRunner(sequence as any, { contextState: {} }, undefined, [])

		// Abort after first action
		const originalRun = runner.run.bind(runner)
		const runPromise = (async () => {
			// We need to abort during execution. Since actions resolve immediately,
			// let's make the first action trigger abort
			const mockInvokeWithAbort = vi.fn(async () => {
				callCount++
				if (callCount === 1) runner.abort()
				return {}
			})
			;(PluginManager.getInstance as any).mockReturnValue({
				getAction: () => ({
					type: "regular",
					configSchema: { type: Object, properties: {} },
					invoke: mockInvokeWithAbort,
				}),
			})
			return runner.run()
		})()

		const result = await runPromise
		expect(result).toBe("aborted")
	})

	it("should report aborted state", () => {
		const runner = new SequenceRunner({ actions: [] } as any, { contextState: {} })
		expect(runner.aborted).toBe(false)
		runner.abort()
		expect(runner.aborted).toBe(true)
	})

	it("should return complete for empty sequence", async () => {
		const runner = new SequenceRunner({ actions: [] } as any, { contextState: {} })
		const result = await runner.run()
		expect(result).toBe("complete")
	})
})
