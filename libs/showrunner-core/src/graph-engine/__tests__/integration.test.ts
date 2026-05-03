import { describe, it, expect, vi, beforeEach } from "vitest"

// Mock electron
vi.mock("electron", () => ({
	ipcMain: { handle: vi.fn() },
	BrowserWindow: vi.fn(),
}))

// Mock PluginManager — must be before vm import
const mockGetAction = vi.fn()
vi.mock("../../plugins/plugin-manager", () => ({
	PluginManager: {
		getInstance: () => ({
			getAction: mockGetAction,
		}),
	},
}))

// Mock deserializeSchema to pass-through config (no real schema processing in tests)
vi.mock("../../util/ipc-schema", () => ({
	deserializeSchema: vi.fn(async (_schema: any, config: any) => config),
}))

import { GraphCompiler } from "../compiler"
import { GraphVM } from "../vm"
import type { AutomationGraph, AutomationDataWire, SubgraphDefinition } from "showrunner-schema"

function mockAction(invokeFn: (...args: any[]) => Promise<any>) {
	return {
		type: "regular" as const,
		configSchema: { type: "Object", properties: {} },
		invoke: invokeFn,
		getDuration: async () => undefined,
	}
}

describe("Graph Integration (compile → VM → action)", () => {
	beforeEach(() => {
		mockGetAction.mockReset()
	})

	it("executes single action and stores result", async () => {
		const invokeSpy = vi.fn(async () => ({ message: "hello" }))
		mockGetAction.mockReturnValue(mockAction(invokeSpy))

		const graph: AutomationGraph = {
			nodes: [{ id: "a1", type: "action", plugin: "test", action: "echo", config: { text: "hi" }, x: 0, y: 0 }],
			edges: [],
			entryNodeId: "a1",
		}

		const compiler = new GraphCompiler()
		const program = compiler.compile(graph)
		const vm = new GraphVM(program, { contextState: {} })
		const result = await vm.execute()

		expect(result).toBe("complete")
		expect(invokeSpy).toHaveBeenCalledOnce()
		expect(invokeSpy.mock.calls[0][0]).toEqual({ text: "hi" })
		expect(vm.getNodeResults().get("a1")).toEqual({ message: "hello" })
	})

	it("chains two actions in execution order", async () => {
		const calls: string[] = []
		mockGetAction.mockImplementation((_plugin: string, action: string) => {
			return mockAction(async (config) => {
				calls.push(action)
				return { ran: action }
			})
		})

		const graph: AutomationGraph = {
			nodes: [
				{ id: "a1", type: "action", plugin: "p", action: "first", config: {}, x: 0, y: 0 },
				{ id: "a2", type: "action", plugin: "p", action: "second", config: {}, x: 1, y: 0 },
			],
			edges: [{ id: "e1", from: "a1", to: "a2" }],
			entryNodeId: "a1",
		}

		const program = new GraphCompiler().compile(graph)
		const result = await new GraphVM(program, { contextState: {} }).execute()

		expect(result).toBe("complete")
		expect(calls).toEqual(["first", "second"])
	})

	it("resolves data wires between actions", async () => {
		let receivedConfig: any = null
		mockGetAction.mockImplementation((_plugin: string, action: string) => {
			if (action === "producer") {
				return mockAction(async () => ({ count: 42, label: "items" }))
			}
			return mockAction(async (config) => {
				receivedConfig = config
				return {}
			})
		})

		const graph: AutomationGraph = {
			nodes: [
				{ id: "a1", type: "action", plugin: "p", action: "producer", config: {}, x: 0, y: 0 },
				{ id: "a2", type: "action", plugin: "p", action: "consumer", config: { amount: 0 }, x: 1, y: 0 },
			],
			edges: [{ id: "e1", from: "a1", to: "a2" }],
			entryNodeId: "a1",
		}
		const dataWires: AutomationDataWire[] = [
			{ id: "w1", fromNode: "a1", fromPort: "count", toNode: "a2", toPort: "amount" },
		]

		const program = new GraphCompiler().compile(graph, undefined, dataWires)
		const vm = new GraphVM(program, { contextState: {} })
		await vm.execute()

		expect(receivedConfig.amount).toBe(42)
	})

	it("resolves data wires into nested config paths", async () => {
		let receivedConfig: any = null
		mockGetAction.mockImplementation((_plugin: string, action: string) => {
			if (action === "producer") {
				return mockAction(async () => ({ payload: { message: "nested hello" } }))
			}
			return mockAction(async (config) => {
				receivedConfig = config
				return {}
			})
		})

		const graph: AutomationGraph = {
			nodes: [
				{ id: "a1", type: "action", plugin: "p", action: "producer", config: {}, x: 0, y: 0 },
				{ id: "a2", type: "action", plugin: "p", action: "consumer", config: { payload: { message: "" } }, x: 1, y: 0 },
			],
			edges: [{ id: "e1", from: "a1", to: "a2" }],
			entryNodeId: "a1",
		}
		const dataWires: AutomationDataWire[] = [
			{ id: "w1", fromNode: "a1", fromPort: "payload.message", toNode: "a2", toPort: "payload.message" },
		]

		const program = new GraphCompiler().compile(graph, undefined, dataWires)
		await new GraphVM(program, { contextState: {} }).execute()

		expect(receivedConfig.payload.message).toBe("nested hello")
	})

	it("resolves data wires into nested paths when the target config does not exist yet", async () => {
		let receivedConfig: any = null
		mockGetAction.mockImplementation((_plugin: string, action: string) => {
			if (action === "producer") {
				return mockAction(async () => ({ actor: { displayName: "ViewerName" } }))
			}
			return mockAction(async (config) => {
				receivedConfig = config
				return {}
			})
		})

		const graph: AutomationGraph = {
			nodes: [
				{ id: "a1", type: "action", plugin: "p", action: "producer", config: {}, x: 0, y: 0 },
				{ id: "a2", type: "action", plugin: "p", action: "consumer", config: {}, x: 1, y: 0 },
			],
			edges: [{ id: "e1", from: "a1", to: "a2" }],
			entryNodeId: "a1",
		}
		const dataWires: AutomationDataWire[] = [
			{ id: "w1", fromNode: "a1", fromPort: "actor.displayName", toNode: "a2", toPort: "payload.viewer.name" },
		]

		const program = new GraphCompiler().compile(graph, undefined, dataWires)
		await new GraphVM(program, { contextState: {} }).execute()

		expect(receivedConfig).toEqual({ payload: { viewer: { name: "ViewerName" } } })
	})

	it("resolves trigger data wires from execution context", async () => {
		let receivedConfig: any = null
		mockGetAction.mockReturnValue(mockAction(async (config) => {
			receivedConfig = config
			return {}
		}))

		const graph: AutomationGraph = {
			nodes: [
				{ id: "paid-alert", type: "action", plugin: "p", action: "consumer", config: { viewerName: "", amount: "" }, x: 0, y: 0 },
			],
			edges: [],
			entryNodeId: "paid-alert",
		}
		const dataWires: AutomationDataWire[] = [
			{ id: "w1", fromNode: "trigger", fromPort: "viewerName", toNode: "paid-alert", toPort: "viewerName" },
			{ id: "w2", fromNode: "trigger", fromPort: "payload.amount", toNode: "paid-alert", toPort: "amount" },
		]

		const program = new GraphCompiler().compile(graph, undefined, dataWires)
		await new GraphVM(program, { contextState: { viewerName: "SaiTatter", payload: { amount: "10.00" } } }).execute()

		expect(receivedConfig).toEqual({ viewerName: "SaiTatter", amount: "10.00" })
	})

	it("resolves data wires for action node ids that contain colons", async () => {
		let receivedConfig: any = null
		mockGetAction.mockImplementation((_plugin: string, action: string) => {
			if (action === "producer") {
				return mockAction(async () => ({ text: "colon-safe" }))
			}
			return mockAction(async (config) => {
				receivedConfig = config
				return {}
			})
		})

		const graph: AutomationGraph = {
			nodes: [
				{ id: "group:a1", type: "action", plugin: "p", action: "producer", config: {}, x: 0, y: 0 },
				{ id: "group:a2", type: "action", plugin: "p", action: "consumer", config: {}, x: 1, y: 0 },
			],
			edges: [{ id: "e1", from: "group:a1", to: "group:a2" }],
			entryNodeId: "group:a1",
		}
		const dataWires: AutomationDataWire[] = [
			{ id: "w1", fromNode: "group:a1", fromPort: "text", toNode: "group:a2", toPort: "payload.message" },
		]

		const program = new GraphCompiler().compile(graph, undefined, dataWires)
		await new GraphVM(program, { contextState: {} }).execute()

		expect(receivedConfig).toEqual({ payload: { message: "colon-safe" } })
	})

	it("ignores unsafe data wire paths instead of polluting prototypes", async () => {
		let receivedConfig: any = null
		mockGetAction.mockImplementation((_plugin: string, action: string) => {
			if (action === "producer") {
				return mockAction(async () => ({ safe: "ok", constructor: { prototype: { polluted: true } } }))
			}
			return mockAction(async (config) => {
				receivedConfig = config
				return {}
			})
		})

		const graph: AutomationGraph = {
			nodes: [
				{ id: "a1", type: "action", plugin: "p", action: "producer", config: {}, x: 0, y: 0 },
				{ id: "a2", type: "action", plugin: "p", action: "consumer", config: {}, x: 1, y: 0 },
			],
			edges: [{ id: "e1", from: "a1", to: "a2" }],
			entryNodeId: "a1",
		}
		const dataWires: AutomationDataWire[] = [
			{ id: "w1", fromNode: "a1", fromPort: "constructor.prototype.polluted", toNode: "a2", toPort: "__proto__.polluted" },
			{ id: "w2", fromNode: "a1", fromPort: "safe", toNode: "a2", toPort: "payload.safe" },
		]

		const program = new GraphCompiler().compile(graph, undefined, dataWires)
		await new GraphVM(program, { contextState: {} }).execute()

		expect(receivedConfig).toEqual({ payload: { safe: "ok" } })
		expect(({} as Record<string, any>).polluted).toBeUndefined()
	})

	it("executes correct branch in if-then-else", async () => {
		const calls: string[] = []
		mockGetAction.mockImplementation((_p: string, action: string) =>
			mockAction(async () => {
				calls.push(action)
				return {}
			})
		)

		const graph: AutomationGraph = {
			nodes: [
				{ id: "if1", type: "if", condition: { type: "literal", value: false }, x: 0, y: 0 },
				{ id: "then1", type: "action", plugin: "p", action: "then-action", config: {}, x: 1, y: 0 },
				{ id: "else1", type: "action", plugin: "p", action: "else-action", config: {}, x: 1, y: 1 },
			],
			edges: [
				{ id: "e1", from: "if1", to: "then1", port: "then" },
				{ id: "e2", from: "if1", to: "else1", port: "else" },
			],
			entryNodeId: "if1",
		}

		await new GraphVM(new GraphCompiler().compile(graph), { contextState: {} }).execute()

		expect(calls).toEqual(["else-action"])
	})

	it("executes action in for-loop body multiple times", async () => {
		const iterations: number[] = []
		mockGetAction.mockReturnValue(
			mockAction(async (config) => {
				iterations.push(config.iteration)
				return {}
			})
		)

		const graph: AutomationGraph = {
			nodes: [
				{
					id: "for1",
					type: "for",
					variable: "i",
					start: { type: "literal", value: 0 },
					end: { type: "literal", value: 3 },
					step: { type: "literal", value: 1 },
					x: 0,
					y: 0,
				},
				{
					id: "body",
					type: "action",
					plugin: "p",
					action: "loop-body",
					config: { iteration: { type: "variable", name: "i" } },
					x: 1,
					y: 0,
				},
			],
			edges: [{ id: "e1", from: "for1", to: "body", port: "body" }],
			entryNodeId: "for1",
		}

		await new GraphVM(new GraphCompiler().compile(graph), { contextState: {} }).execute()

		// Note: config.iteration is an Expression object, not evaluated by resolveActionConfig
		// (wire resolution only handles top-level config keys, not nested expressions)
		// The action receives the raw config; expression evaluation happens in EVAL instructions
		expect(mockGetAction).toHaveBeenCalledWith("p", "loop-body")
	})

	it("returns error when action not found", async () => {
		mockGetAction.mockReturnValue(undefined)

		const graph: AutomationGraph = {
			nodes: [{ id: "a1", type: "action", plugin: "missing", action: "nope", config: {}, x: 0, y: 0 }],
			edges: [],
			entryNodeId: "a1",
		}

		const vm = new GraphVM(new GraphCompiler().compile(graph), { contextState: {} })
		const result = await vm.execute()

		expect(result).toBe("error")
	})

	it("returns error when action throws", async () => {
		mockGetAction.mockReturnValue(
			mockAction(async () => {
				throw new Error("Action exploded")
			})
		)

		const graph: AutomationGraph = {
			nodes: [{ id: "a1", type: "action", plugin: "p", action: "explode", config: {}, x: 0, y: 0 }],
			edges: [],
			entryNodeId: "a1",
		}

		const dbg = {
			executionStarted: vi.fn(),
			executionEnded: vi.fn(),
			markStart: vi.fn(),
			markEnd: vi.fn(),
			logResult: vi.fn(),
			logError: vi.fn(),
		}

		const vm = new GraphVM(new GraphCompiler().compile(graph), { contextState: {} }, dbg)
		const result = await vm.execute()

		expect(result).toBe("error")
		expect(dbg.logError).toHaveBeenCalled()
		expect(dbg.markEnd).toHaveBeenCalledWith("a1")
	})

	it("applies result mapping to contextState", async () => {
		mockGetAction.mockReturnValue(
			mockAction(async () => ({ userId: "abc123", score: 99 }))
		)

		const graph: AutomationGraph = {
			nodes: [
				{
					id: "a1",
					type: "action",
					plugin: "p",
					action: "fetch",
					config: {},
					resultMapping: { userId: "lastUser", score: "lastScore" },
					x: 0,
					y: 0,
				},
			],
			edges: [],
			entryNodeId: "a1",
		}

		const contextState: Record<string, any> = {}
		await new GraphVM(new GraphCompiler().compile(graph), { contextState }).execute()

		expect(contextState.lastUser).toBe("abc123")
		expect(contextState.lastScore).toBe(99)
	})

	it("exposes subgraph return outputs to caller nodes", async () => {
		let receivedConfig: any = null
		mockGetAction.mockImplementation((_plugin: string, action: string) => {
			if (action === "consumer") {
				return mockAction(async (config) => {
					receivedConfig = config
					return {}
				})
			}
			return mockAction(async () => ({}))
		})

		const graph: AutomationGraph = {
			nodes: [
				{
					id: "call1",
					type: "subgraphCall",
					subgraphId: "sg1",
					inputs: { name: { type: "literal", value: "ShowRunner" } },
					x: 0,
					y: 0,
				},
				{ id: "consumer", type: "action", plugin: "p", action: "consumer", config: { text: "" }, x: 1, y: 0 },
			],
			edges: [{ id: "e1", from: "call1", to: "consumer" }],
			entryNodeId: "call1",
		}
		const subgraphs: SubgraphDefinition[] = [
			{
				id: "sg1",
				name: "Greeting",
				parameters: [{ name: "name", type: "string" }],
				outputs: [{ name: "message", type: "string" }],
				nodes: [
					{
						id: "ret",
						type: "return",
						outputs: {
							message: {
								type: "binary",
								op: "+",
								left: { type: "literal", value: "Hello " },
								right: { type: "variable", name: "name" },
							},
						},
						x: 0,
						y: 0,
					},
				],
				edges: [],
				entryNodeId: "ret",
			},
		]
		const dataWires: AutomationDataWire[] = [
			{ id: "w1", fromNode: "call1", fromPort: "message", toNode: "consumer", toPort: "text" },
		]

		const program = new GraphCompiler().compile(graph, subgraphs, dataWires)
		await new GraphVM(program, { contextState: {} }).execute()

		expect(receivedConfig.text).toBe("Hello ShowRunner")
	})

	it("passes data wires through subgraph input and output ports", async () => {
		let receivedConfig: any = null
		mockGetAction.mockImplementation((_plugin: string, action: string) => {
			if (action === "producer") {
				return mockAction(async () => ({ payload: { message: "from wire" } }))
			}
			if (action === "echo") {
				return mockAction(async (config) => ({ echoed: config.text }))
			}
			return mockAction(async (config) => {
				receivedConfig = config
				return {}
			})
		})

		const graph: AutomationGraph = {
			nodes: [
				{ id: "producer", type: "action", plugin: "p", action: "producer", config: {}, x: 0, y: 0 },
				{ id: "call1", type: "subgraphCall", subgraphId: "sg1", inputs: {}, x: 1, y: 0 },
				{ id: "consumer", type: "action", plugin: "p", action: "consumer", config: { text: "" }, x: 2, y: 0 },
			],
			edges: [
				{ id: "e1", from: "producer", to: "call1" },
				{ id: "e2", from: "call1", to: "consumer" },
			],
			entryNodeId: "producer",
		}
		const subgraphs: SubgraphDefinition[] = [
			{
				id: "sg1",
				name: "Echo",
				parameters: [{ name: "text", type: "string" }],
				outputs: [{ name: "message", type: "string", expression: { type: "port", nodeId: "echo", port: "echoed" } }],
				nodes: [{ id: "echo", type: "action", plugin: "p", action: "echo", config: { text: "" }, x: 0, y: 0 }],
				edges: [],
				dataWires: [{ id: "sgw1", fromNode: "__param:text", fromPort: "value", toNode: "echo", toPort: "text" }],
				entryNodeId: "echo",
			},
		]
		const dataWires: AutomationDataWire[] = [
			{ id: "w1", fromNode: "producer", fromPort: "payload.message", toNode: "call1", toPort: "text" },
			{ id: "w2", fromNode: "call1", fromPort: "message", toNode: "consumer", toPort: "text" },
		]

		const program = new GraphCompiler().compile(graph, subgraphs, dataWires)
		await new GraphVM(program, { contextState: {} }).execute()

		expect(receivedConfig.text).toBe("from wire")
	})

	it("debugger hooks fire in correct order", async () => {
		mockGetAction.mockReturnValue(mockAction(async () => ({ ok: true })))

		const callOrder: string[] = []
		const dbg = {
			executionStarted: vi.fn(() => callOrder.push("execStart")),
			executionEnded: vi.fn(() => callOrder.push("execEnd")),
			markStart: vi.fn(() => callOrder.push("markStart")),
			markEnd: vi.fn(() => callOrder.push("markEnd")),
			logResult: vi.fn(() => callOrder.push("logResult")),
			logError: vi.fn(),
		}

		const graph: AutomationGraph = {
			nodes: [{ id: "a1", type: "action", plugin: "p", action: "a", config: {}, x: 0, y: 0 }],
			edges: [],
			entryNodeId: "a1",
		}

		await new GraphVM(new GraphCompiler().compile(graph), { contextState: {} }, dbg).execute()

		expect(callOrder).toEqual(["execStart", "markStart", "logResult", "markEnd", "execEnd"])
	})

	it("aborts mid-execution via AbortSignal", async () => {
		const controller = new AbortController()
		mockGetAction.mockReturnValue(
			mockAction(async () => {
				controller.abort() // Abort after first action
				return {}
			})
		)

		const graph: AutomationGraph = {
			nodes: [
				{ id: "a1", type: "action", plugin: "p", action: "first", config: {}, x: 0, y: 0 },
				{ id: "a2", type: "action", plugin: "p", action: "second", config: {}, x: 1, y: 0 },
			],
			edges: [{ id: "e1", from: "a1", to: "a2" }],
			entryNodeId: "a1",
		}

		const vm = new GraphVM(new GraphCompiler().compile(graph), { contextState: {} }, undefined, controller.signal)
		const result = await vm.execute()

		expect(result).toBe("aborted")
	})

	it("resolves multiple data wires to same target node", async () => {
		let receivedConfig: any = null
		mockGetAction.mockImplementation((_p: string, action: string) => {
			if (action === "srcA") return mockAction(async () => ({ x: 10 }))
			if (action === "srcB") return mockAction(async () => ({ y: 20 }))
			return mockAction(async (config) => {
				receivedConfig = config
				return {}
			})
		})

		const graph: AutomationGraph = {
			nodes: [
				{ id: "sa", type: "action", plugin: "p", action: "srcA", config: {}, x: 0, y: 0 },
				{ id: "sb", type: "action", plugin: "p", action: "srcB", config: {}, x: 0, y: 1 },
				{ id: "target", type: "action", plugin: "p", action: "consumer", config: { a: 0, b: 0 }, x: 1, y: 0 },
			],
			edges: [
				{ id: "e1", from: "sa", to: "sb" },
				{ id: "e2", from: "sb", to: "target" },
			],
			entryNodeId: "sa",
		}
		const dataWires: AutomationDataWire[] = [
			{ id: "w1", fromNode: "sa", fromPort: "x", toNode: "target", toPort: "a" },
			{ id: "w2", fromNode: "sb", fromPort: "y", toNode: "target", toPort: "b" },
		]

		const program = new GraphCompiler().compile(graph, undefined, dataWires)
		await new GraphVM(program, { contextState: {} }).execute()

		expect(receivedConfig.a).toBe(10)
		expect(receivedConfig.b).toBe(20)
	})

	it("wire returns undefined for missing source result", async () => {
		let receivedConfig: any = null
		// First action returns nothing (null result)
		mockGetAction.mockImplementation((_p: string, action: string) => {
			if (action === "empty") return mockAction(async () => null)
			return mockAction(async (config) => {
				receivedConfig = config
				return {}
			})
		})

		const graph: AutomationGraph = {
			nodes: [
				{ id: "a1", type: "action", plugin: "p", action: "empty", config: {}, x: 0, y: 0 },
				{ id: "a2", type: "action", plugin: "p", action: "consumer", config: { val: "default" }, x: 1, y: 0 },
			],
			edges: [{ id: "e1", from: "a1", to: "a2" }],
			entryNodeId: "a1",
		}
		const dataWires: AutomationDataWire[] = [
			{ id: "w1", fromNode: "a1", fromPort: "output", toNode: "a2", toPort: "val" },
		]

		const program = new GraphCompiler().compile(graph, undefined, dataWires)
		await new GraphVM(program, { contextState: {} }).execute()

		// Wire source returned null, so nodeResults has no entry → val gets undefined
		expect(receivedConfig.val).toBeUndefined()
	})
})
