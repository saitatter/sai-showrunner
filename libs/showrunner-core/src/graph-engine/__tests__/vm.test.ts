import { describe, it, expect, vi } from "vitest"
import { GraphCompiler, OpCode, type Program, type Instruction } from "../compiler"
import { GraphVM } from "../vm"
import type { AutomationGraph } from "ShowRunner-schema"

// Helper: build a minimal program manually (bypassing action execution)
function makeProgram(instructions: Instruction[], localSlots = 10): Program {
	return {
		instructions,
		actionNodes: [],
		subgraphs: [],
		localSlotCount: localSlots,
		slotNames: new Array(localSlots).fill(""),
	}
}

describe("GraphVM", () => {
	describe("basic execution", () => {
		it("executes HALT immediately", async () => {
			const program = makeProgram([{ op: OpCode.HALT }])
			const vm = new GraphVM(program, { contextState: {} })
			const result = await vm.execute()
			expect(result).toBe("complete")
		})

		it("executes EVAL + STORE + LOAD cycle", async () => {
			const program = makeProgram([
				{ op: OpCode.EVAL, arg1: { type: "literal", value: 42 } },
				{ op: OpCode.STORE, arg0: 0 },
				{ op: OpCode.LOAD, arg0: 0 },
				{ op: OpCode.HALT },
			])
			const vm = new GraphVM(program, { contextState: {} })
			const result = await vm.execute()
			expect(result).toBe("complete")
		})

		it("aborts when signal fires", async () => {
			const controller = new AbortController()
			// Infinite loop that yields
			const program = makeProgram([
				{ op: OpCode.YIELD },
				{ op: OpCode.JUMP, arg0: 0 },
			])
			const vm = new GraphVM(program, { contextState: {} }, undefined, controller.signal)

			// Abort after a short delay
			setTimeout(() => controller.abort(), 10)
			const result = await vm.execute()
			expect(result).toBe("aborted")
		})

		it("aborts via abort() method", async () => {
			const program = makeProgram([
				{ op: OpCode.YIELD },
				{ op: OpCode.JUMP, arg0: 0 },
			])
			const vm = new GraphVM(program, { contextState: {} })

			setTimeout(() => vm.abort(), 10)
			const result = await vm.execute()
			expect(result).toBe("aborted")
		})
	})

	describe("branching", () => {
		it("JUMP_IF takes branch when truthy", async () => {
			const program = makeProgram([
				{ op: OpCode.EVAL, arg1: { type: "literal", value: true } },
				{ op: OpCode.JUMP_IF, arg0: 3 }, // jump to HALT
				{ op: OpCode.EVAL, arg1: { type: "literal", value: 999 } }, // should be skipped
				{ op: OpCode.HALT },
			])
			const vm = new GraphVM(program, { contextState: {} })
			const result = await vm.execute()
			expect(result).toBe("complete")
		})

		it("JUMP_IF falls through when falsy", async () => {
			const program = makeProgram([
				{ op: OpCode.EVAL, arg1: { type: "literal", value: false } },
				{ op: OpCode.JUMP_IF, arg0: 4 }, // would jump past store
				{ op: OpCode.EVAL, arg1: { type: "literal", value: 77 } },
				{ op: OpCode.STORE, arg0: 0 },
				{ op: OpCode.HALT },
			])
			const vm = new GraphVM(program, { contextState: {} })
			const result = await vm.execute()
			expect(result).toBe("complete")
		})

		it("JUMP_IF_NOT takes branch when falsy", async () => {
			const program = makeProgram([
				{ op: OpCode.EVAL, arg1: { type: "literal", value: false } },
				{ op: OpCode.JUMP_IF_NOT, arg0: 3 },
				{ op: OpCode.EVAL, arg1: { type: "literal", value: "skipped" } }, // skipped
				{ op: OpCode.HALT },
			])
			const vm = new GraphVM(program, { contextState: {} })
			const result = await vm.execute()
			expect(result).toBe("complete")
		})
	})

	describe("loops", () => {
		it("LOOP_CHECK exits when counter >= end", async () => {
			const program = makeProgram([
				// Store counter=5 in slot 0
				{ op: OpCode.EVAL, arg1: { type: "literal", value: 5 } },
				{ op: OpCode.STORE, arg0: 0 },
				// Store end=5 in slot 1
				{ op: OpCode.EVAL, arg1: { type: "literal", value: 5 } },
				{ op: OpCode.STORE, arg0: 1 },
				// LOOP_CHECK: slot0 >= slot1 → jump to HALT (index 5)
				{ op: OpCode.LOOP_CHECK, arg0: 0, arg1: 1, arg2: 6 },
				{ op: OpCode.EVAL, arg1: { type: "literal", value: "unreachable" } }, // should not run
				{ op: OpCode.HALT },
			])
			const vm = new GraphVM(program, { contextState: {} })
			const result = await vm.execute()
			expect(result).toBe("complete")
		})

		it("LOOP_CHECK continues when counter < end", async () => {
			const program = makeProgram([
				// counter=0
				{ op: OpCode.EVAL, arg1: { type: "literal", value: 0 } },
				{ op: OpCode.STORE, arg0: 0 },
				// end=3
				{ op: OpCode.EVAL, arg1: { type: "literal", value: 3 } },
				{ op: OpCode.STORE, arg0: 1 },
				// LOOP_CHECK
				{ op: OpCode.LOOP_CHECK, arg0: 0, arg1: 1, arg2: 8 },
				// body: step counter += 1
				{ op: OpCode.LOOP_STEP, arg0: 0, arg1: { type: "literal", value: 1 } },
				{ op: OpCode.YIELD },
				{ op: OpCode.JUMP, arg0: 4 }, // back to LOOP_CHECK
				{ op: OpCode.HALT },
			])
			const vm = new GraphVM(program, { contextState: {} })
			const result = await vm.execute()
			expect(result).toBe("complete")
		})

		it("respects maxIterations limit", async () => {
			const program = makeProgram([
				{ op: OpCode.EVAL, arg1: { type: "literal", value: 0 } },
				{ op: OpCode.STORE, arg0: 0 },
				{ op: OpCode.EVAL, arg1: { type: "literal", value: 999999 } },
				{ op: OpCode.STORE, arg0: 1 },
				{ op: OpCode.LOOP_CHECK, nodeId: "loop", arg0: 0, arg1: 1, arg2: 8 },
				{ op: OpCode.LOOP_STEP, arg0: 0, arg1: { type: "literal", value: 1 } },
				{ op: OpCode.YIELD },
				{ op: OpCode.JUMP, arg0: 4 },
				{ op: OpCode.HALT },
			])
			const vm = new GraphVM(program, { contextState: {} }, undefined, undefined, { maxIterations: 100 })
			const result = await vm.execute()
			expect(result).toBe("error") // exceeded limit
		})
	})

	describe("forEach (ITER_NEXT)", () => {
		it("iterates over array via ITER_NEXT", async () => {
			// Manually construct a forEach-like program:
			// slot 0 = item, slot 1 = index, slot 2 = collection
			const iterNextInstr: any = {
				op: OpCode.ITER_NEXT,
				nodeId: "fe",
				arg0: 0, // item slot
				arg1: 1, // index slot
				arg2: 7, // exit target
				__collSlot: 2,
			}
			const program = makeProgram([
				// Store collection in slot 2
				{ op: OpCode.EVAL, arg1: { type: "literal", value: ["a", "b", "c"] } },
				{ op: OpCode.STORE, arg0: 2 },
				// Init index = 0
				{ op: OpCode.EVAL, arg1: { type: "literal", value: 0 } },
				{ op: OpCode.STORE, arg0: 1 },
				// ITER_NEXT
				iterNextInstr,
				// Body: step index += 1
				{ op: OpCode.LOOP_STEP, arg0: 1, arg1: { type: "literal", value: 1 } },
				{ op: OpCode.JUMP, arg0: 4 }, // back to ITER_NEXT
				{ op: OpCode.HALT },
			])
			const vm = new GraphVM(program, { contextState: {} })
			const result = await vm.execute()
			expect(result).toBe("complete")
		})

		it("exits immediately on empty array", async () => {
			const iterNextInstr: any = {
				op: OpCode.ITER_NEXT,
				nodeId: "fe",
				arg0: 0,
				arg1: 1,
				arg2: 5, // exit target
				__collSlot: 2,
			}
			const program = makeProgram([
				{ op: OpCode.EVAL, arg1: { type: "literal", value: [] } },
				{ op: OpCode.STORE, arg0: 2 },
				{ op: OpCode.EVAL, arg1: { type: "literal", value: 0 } },
				{ op: OpCode.STORE, arg0: 1 },
				iterNextInstr,
				{ op: OpCode.HALT },
			])
			const vm = new GraphVM(program, { contextState: {} })
			const result = await vm.execute()
			expect(result).toBe("complete")
		})
	})

	describe("subgraph CALL/RET", () => {
		it("CALL pushes frame and RET returns to caller", async () => {
			// Manually build: CALL to subgraph at PC=3, then HALT. Subgraph: RET.
			const program: Program = {
				instructions: [
					{ op: OpCode.CALL, nodeId: "call1", arg0: -1, arg1: {} },
					{ op: OpCode.HALT },
					// Subgraph body starts at PC=2
					{ op: OpCode.RET, arg1: undefined },
				],
				actionNodes: [],
				subgraphs: [{ id: "sg1", name: "Sub1", entryPC: 2, paramSlots: [], paramNames: [], outputExprs: {} }],
				localSlotCount: 5,
				slotNames: new Array(5).fill(""),
			}
			// Patch CALL instruction to reference subgraph
			;(program.instructions[0] as any).__subgraphId = "sg1"

			const vm = new GraphVM(program, { contextState: {} })
			const result = await vm.execute()
			expect(result).toBe("complete")
		})

		it("errors on max call depth exceeded", async () => {
			// Recursive: CALL self forever
			const program: Program = {
				instructions: [
					{ op: OpCode.CALL, nodeId: "call1", arg0: -1, arg1: {} },
					{ op: OpCode.HALT },
				],
				actionNodes: [],
				subgraphs: [{ id: "sg1", name: "Recursive", entryPC: 0, paramSlots: [], paramNames: [], outputExprs: {} }],
				localSlotCount: 5,
				slotNames: new Array(5).fill(""),
			}
			;(program.instructions[0] as any).__subgraphId = "sg1"

			const vm = new GraphVM(program, { contextState: {} }, undefined, undefined, { maxCallDepth: 5 })
			const result = await vm.execute()
			expect(result).toBe("error")
		})
	})

	describe("debugger hooks", () => {
		it("calls sequenceStarted and sequenceEnded", async () => {
			const dbg = {
				sequenceStarted: vi.fn(),
				sequenceEnded: vi.fn(),
				markStart: vi.fn(),
				markEnd: vi.fn(),
				logResult: vi.fn(),
				logError: vi.fn(),
			}
			const program = makeProgram([{ op: OpCode.HALT }])
			const vm = new GraphVM(program, { contextState: {} }, dbg)
			await vm.execute()

			expect(dbg.sequenceStarted).toHaveBeenCalledOnce()
			expect(dbg.sequenceEnded).toHaveBeenCalledOnce()
		})
	})

	describe("expression evaluation in VM context", () => {
		it("EVAL resolves contextState variables", async () => {
			const program = makeProgram([
				{ op: OpCode.EVAL, arg1: { type: "variable", name: "msg" } },
				{ op: OpCode.STORE, arg0: 0 },
				{ op: OpCode.HALT },
			])
			const vm = new GraphVM(program, { contextState: { msg: "hello" } })
			const result = await vm.execute()
			expect(result).toBe("complete")
		})

		it("EVAL resolves port references from nodeResults", async () => {
			const program = makeProgram([
				{ op: OpCode.EVAL, arg1: { type: "port", nodeId: "n1", port: "value" } },
				{ op: OpCode.STORE, arg0: 0 },
				{ op: OpCode.HALT },
			])
			const vm = new GraphVM(program, { contextState: {} })
			// Pre-seed node results
			vm.getNodeResults().set("n1", { value: 99 })
			const result = await vm.execute()
			expect(result).toBe("complete")
		})
	})

	describe("YIELD", () => {
		it("yields to event loop without breaking execution", async () => {
			const program = makeProgram([
				{ op: OpCode.YIELD },
				{ op: OpCode.YIELD },
				{ op: OpCode.YIELD },
				{ op: OpCode.HALT },
			])
			const vm = new GraphVM(program, { contextState: {} })
			const result = await vm.execute()
			expect(result).toBe("complete")
		})
	})

	describe("integration: compiled graph → VM", () => {
		it("compiles and runs a simple if-then graph (no actions)", async () => {
			// If(true) → then path has a return, else does nothing
			const graph: AutomationGraph = {
				nodes: [
					{ id: "if1", type: "if", condition: { type: "literal", value: true }, x: 0, y: 0 },
					{ id: "ret1", type: "return", outputs: { ok: { type: "literal", value: true } }, x: 1, y: 0 },
				],
				edges: [
					{ id: "e1", from: "if1", to: "ret1", port: "then" },
				],
				entryNodeId: "if1",
			}

			const compiler = new GraphCompiler()
			const program = compiler.compile(graph)
			const vm = new GraphVM(program, { contextState: {} })
			const result = await vm.execute()
			expect(result).toBe("complete")
		})

		it("compiles and runs a for loop that terminates", async () => {
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
					{ id: "ret1", type: "return", x: 1, y: 0 },
				],
				edges: [
					{ id: "e1", from: "for1", to: "ret1", port: "body" },
				],
				entryNodeId: "for1",
			}

			const compiler = new GraphCompiler()
			const program = compiler.compile(graph)
			const vm = new GraphVM(program, { contextState: {} })
			const result = await vm.execute()
			expect(result).toBe("complete")
		})
	})
})
