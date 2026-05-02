import { describe, it, expect } from "vitest"
import { GraphCompiler, OpCode } from "../compiler"
import type { AutomationGraph, GraphNode, GraphEdge, AutomationDataWire } from "ShowRunner-schema"

function makeGraph(nodes: GraphNode[], edges: GraphEdge[], entryNodeId: string): AutomationGraph {
	return { nodes, edges, entryNodeId }
}

describe("GraphCompiler", () => {
	describe("linear sequence", () => {
		it("compiles single action to EXEC + HALT", () => {
			const graph = makeGraph(
				[{ id: "a1", type: "action", plugin: "test", action: "say", config: {}, x: 0, y: 0 }],
				[],
				"a1"
			)
			const compiler = new GraphCompiler()
			const program = compiler.compile(graph)

			expect(program.instructions.length).toBe(2) // EXEC + HALT
			expect(program.instructions[0].op).toBe(OpCode.EXEC)
			expect(program.instructions[0].nodeId).toBe("a1")
			expect(program.instructions[1].op).toBe(OpCode.HALT)
		})

		it("compiles chain of 3 actions in order", () => {
			const graph = makeGraph(
				[
					{ id: "a1", type: "action", plugin: "p", action: "a", config: {}, x: 0, y: 0 },
					{ id: "a2", type: "action", plugin: "p", action: "b", config: {}, x: 1, y: 0 },
					{ id: "a3", type: "action", plugin: "p", action: "c", config: {}, x: 2, y: 0 },
				],
				[
					{ id: "e1", from: "a1", to: "a2" },
					{ id: "e2", from: "a2", to: "a3" },
				],
				"a1"
			)
			const compiler = new GraphCompiler()
			const program = compiler.compile(graph)

			const execInstrs = program.instructions.filter((i) => i.op === OpCode.EXEC)
			expect(execInstrs.length).toBe(3)
			expect(execInstrs[0].nodeId).toBe("a1")
			expect(execInstrs[1].nodeId).toBe("a2")
			expect(execInstrs[2].nodeId).toBe("a3")
		})
	})

	describe("if branching", () => {
		it("compiles if node with then/else branches", () => {
			const graph = makeGraph(
				[
					{ id: "if1", type: "if", condition: { type: "literal", value: true }, x: 0, y: 0 },
					{ id: "then1", type: "action", plugin: "p", action: "then", config: {}, x: 1, y: 0 },
					{ id: "else1", type: "action", plugin: "p", action: "else", config: {}, x: 1, y: 1 },
				],
				[
					{ id: "e1", from: "if1", to: "then1", port: "then" },
					{ id: "e2", from: "if1", to: "else1", port: "else" },
				],
				"if1"
			)
			const compiler = new GraphCompiler()
			const program = compiler.compile(graph)

			// Should have EVAL, JUMP_IF_NOT, EXEC(then), JUMP, EXEC(else), HALT
			expect(program.instructions.some((i) => i.op === OpCode.EVAL)).toBe(true)
			expect(program.instructions.some((i) => i.op === OpCode.JUMP_IF_NOT)).toBe(true)
			const execInstrs = program.instructions.filter((i) => i.op === OpCode.EXEC)
			expect(execInstrs.length).toBe(2)
		})

		it("compiles if without else branch", () => {
			const graph = makeGraph(
				[
					{ id: "if1", type: "if", condition: { type: "literal", value: true }, x: 0, y: 0 },
					{ id: "then1", type: "action", plugin: "p", action: "then", config: {}, x: 1, y: 0 },
				],
				[
					{ id: "e1", from: "if1", to: "then1", port: "then" },
				],
				"if1"
			)
			const compiler = new GraphCompiler()
			const program = compiler.compile(graph)

			const execInstrs = program.instructions.filter((i) => i.op === OpCode.EXEC)
			expect(execInstrs.length).toBe(1)
			expect(execInstrs[0].nodeId).toBe("then1")
		})
	})

	describe("for loop", () => {
		it("compiles for loop with body", () => {
			const graph = makeGraph(
				[
					{
						id: "for1",
						type: "for",
						variable: "i",
						start: { type: "literal", value: 0 },
						end: { type: "literal", value: 5 },
						step: { type: "literal", value: 1 },
						x: 0,
						y: 0,
					},
					{ id: "body1", type: "action", plugin: "p", action: "body", config: {}, x: 1, y: 0 },
				],
				[
					{ id: "e1", from: "for1", to: "body1", port: "body" },
				],
				"for1"
			)
			const compiler = new GraphCompiler()
			const program = compiler.compile(graph)

			expect(program.instructions.some((i) => i.op === OpCode.LOOP_CHECK)).toBe(true)
			expect(program.instructions.some((i) => i.op === OpCode.LOOP_STEP)).toBe(true)
			expect(program.instructions.some((i) => i.op === OpCode.YIELD)).toBe(true)
			expect(program.instructions.some((i) => i.op === OpCode.EXEC && i.nodeId === "body1")).toBe(true)
		})

		it("compiles for loop with next node after loop", () => {
			const graph = makeGraph(
				[
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
					{ id: "body1", type: "action", plugin: "p", action: "body", config: {}, x: 1, y: 0 },
					{ id: "after1", type: "action", plugin: "p", action: "after", config: {}, x: 2, y: 0 },
				],
				[
					{ id: "e1", from: "for1", to: "body1", port: "body" },
					{ id: "e2", from: "for1", to: "after1", port: "next" },
				],
				"for1"
			)
			const compiler = new GraphCompiler()
			const program = compiler.compile(graph)

			const execInstrs = program.instructions.filter((i) => i.op === OpCode.EXEC)
			expect(execInstrs.length).toBe(2)
			expect(execInstrs.some((i) => i.nodeId === "body1")).toBe(true)
			expect(execInstrs.some((i) => i.nodeId === "after1")).toBe(true)
		})
	})

	describe("forEach loop", () => {
		it("compiles forEach with body", () => {
			const graph = makeGraph(
				[
					{
						id: "fe1",
						type: "forEach",
						variable: "item",
						collection: { type: "literal", value: [1, 2, 3] },
						x: 0,
						y: 0,
					},
					{ id: "body1", type: "action", plugin: "p", action: "body", config: {}, x: 1, y: 0 },
				],
				[
					{ id: "e1", from: "fe1", to: "body1", port: "body" },
				],
				"fe1"
			)
			const compiler = new GraphCompiler()
			const program = compiler.compile(graph)

			expect(program.instructions.some((i) => i.op === OpCode.ITER_NEXT)).toBe(true)
			const iterNext = program.instructions.find((i) => i.op === OpCode.ITER_NEXT)
			expect(iterNext?.arg1).toEqual({ indexSlot: expect.any(Number), collSlot: expect.any(Number) })
			expect(program.instructions.some((i) => i.op === OpCode.YIELD)).toBe(true)
		})
	})

	describe("while loop", () => {
		it("compiles while with condition and body", () => {
			const graph = makeGraph(
				[
					{
						id: "w1",
						type: "while",
						condition: { type: "literal", value: true },
						x: 0,
						y: 0,
					},
					{ id: "body1", type: "action", plugin: "p", action: "body", config: {}, x: 1, y: 0 },
				],
				[
					{ id: "e1", from: "w1", to: "body1", port: "body" },
				],
				"w1"
			)
			const compiler = new GraphCompiler()
			const program = compiler.compile(graph)

			expect(program.instructions.some((i) => i.op === OpCode.EVAL)).toBe(true)
			expect(program.instructions.some((i) => i.op === OpCode.JUMP_IF_NOT)).toBe(true)
			expect(program.instructions.some((i) => i.op === OpCode.JUMP)).toBe(true)
			expect(program.instructions.some((i) => i.op === OpCode.YIELD)).toBe(true)
		})
	})

	describe("break and continue", () => {
		it("compiles break inside for loop", () => {
			const graph = makeGraph(
				[
					{
						id: "for1",
						type: "for",
						variable: "i",
						start: { type: "literal", value: 0 },
						end: { type: "literal", value: 10 },
						step: { type: "literal", value: 1 },
						x: 0,
						y: 0,
					},
					{ id: "brk", type: "break", x: 1, y: 0 },
				],
				[
					{ id: "e1", from: "for1", to: "brk", port: "body" },
				],
				"for1"
			)
			const compiler = new GraphCompiler()
			const program = compiler.compile(graph)

			// Break emits a JUMP to the loop exit
			const jumps = program.instructions.filter((i) => i.op === OpCode.JUMP)
			expect(jumps.length).toBeGreaterThanOrEqual(2) // continue-to-header + break-to-exit
		})

		it("compiles continue inside for loop", () => {
			const graph = makeGraph(
				[
					{
						id: "for1",
						type: "for",
						variable: "i",
						start: { type: "literal", value: 0 },
						end: { type: "literal", value: 10 },
						step: { type: "literal", value: 1 },
						x: 0,
						y: 0,
					},
					{ id: "cnt", type: "continue", x: 1, y: 0 },
				],
				[
					{ id: "e1", from: "for1", to: "cnt", port: "body" },
				],
				"for1"
			)
			const compiler = new GraphCompiler()
			const program = compiler.compile(graph)

			const jumps = program.instructions.filter((i) => i.op === OpCode.JUMP)
			expect(jumps.length).toBeGreaterThanOrEqual(2)
		})
	})

	describe("switch", () => {
		it("compiles switch with multiple cases", () => {
			const graph = makeGraph(
				[
					{
						id: "sw1",
						type: "switch",
						expression: { type: "variable", name: "x" },
						cases: [
							{ value: 1, port: "case:0" },
							{ value: 2, port: "case:1" },
						],
						x: 0,
						y: 0,
					},
					{ id: "c0", type: "action", plugin: "p", action: "case0", config: {}, x: 1, y: 0 },
					{ id: "c1", type: "action", plugin: "p", action: "case1", config: {}, x: 1, y: 1 },
					{ id: "def", type: "action", plugin: "p", action: "default", config: {}, x: 1, y: 2 },
				],
				[
					{ id: "e0", from: "sw1", to: "c0", port: "case:0" },
					{ id: "e1", from: "sw1", to: "c1", port: "case:1" },
					{ id: "e2", from: "sw1", to: "def", port: "default" },
				],
				"sw1"
			)
			const compiler = new GraphCompiler()
			const program = compiler.compile(graph)

			const execInstrs = program.instructions.filter((i) => i.op === OpCode.EXEC)
			expect(execInstrs.length).toBe(3) // case0, case1, default
		})
	})

	describe("subgraph", () => {
		it("compiles subgraph call", () => {
			const graph = makeGraph(
				[
					{
						id: "call1",
						type: "subgraphCall",
						subgraphId: "sg1",
						inputs: { x: { type: "literal", value: 42 } },
						x: 0,
						y: 0,
					},
				],
				[],
				"call1"
			)
			const compiler = new GraphCompiler()
			const program = compiler.compile(graph, [
				{
					id: "sg1",
					name: "MySub",
					parameters: [{ name: "x", type: "number" }],
					outputs: [],
					nodes: [{ id: "sg_a1", type: "action", plugin: "p", action: "inner", config: {}, x: 0, y: 0 }],
					edges: [],
					entryNodeId: "sg_a1",
				},
			])

			const call = program.instructions.find((i) => i.op === OpCode.CALL)
			expect(call?.arg0).toBe(0)
			expect(program.subgraphs.length).toBe(1)
			expect(program.subgraphs[0].id).toBe("sg1")
		})
	})

	describe("return", () => {
		it("compiles return node as RET instruction", () => {
			const graph = makeGraph(
				[
					{ id: "a1", type: "action", plugin: "p", action: "a", config: {}, x: 0, y: 0 },
					{ id: "ret1", type: "return", outputs: { result: { type: "literal", value: 42 } }, x: 1, y: 0 },
				],
				[
					{ id: "e1", from: "a1", to: "ret1" },
				],
				"a1"
			)
			const compiler = new GraphCompiler()
			const program = compiler.compile(graph)

			expect(program.instructions.some((i) => i.op === OpCode.RET)).toBe(true)
		})
	})

	describe("empty graph", () => {
		it("compiles empty graph to just HALT", () => {
			const graph = makeGraph([], [], "missing")
			const compiler = new GraphCompiler()
			const program = compiler.compile(graph)

			expect(program.instructions.length).toBe(1)
			expect(program.instructions[0].op).toBe(OpCode.HALT)
		})
	})

	describe("YIELD insertion", () => {
		it("inserts YIELD in loops", () => {
			const graph = makeGraph(
				[
					{
						id: "w1",
						type: "while",
						condition: { type: "literal", value: true },
						x: 0,
						y: 0,
					},
					{ id: "body1", type: "action", plugin: "p", action: "body", config: {}, x: 1, y: 0 },
				],
				[
					{ id: "e1", from: "w1", to: "body1", port: "body" },
				],
				"w1"
			)
			const compiler = new GraphCompiler()
			const program = compiler.compile(graph)

			const yields = program.instructions.filter((i) => i.op === OpCode.YIELD)
			expect(yields.length).toBeGreaterThanOrEqual(1)
		})
	})

	describe("nested loops", () => {
		it("compiles nested for loops with same variable name", () => {
			const graph = makeGraph(
				[
					{
						id: "outer",
						type: "for",
						variable: "i",
						start: { type: "literal", value: 0 },
						end: { type: "literal", value: 3 },
						step: { type: "literal", value: 1 },
						x: 0,
						y: 0,
					},
					{
						id: "inner",
						type: "for",
						variable: "i",
						start: { type: "literal", value: 0 },
						end: { type: "literal", value: 2 },
						step: { type: "literal", value: 1 },
						x: 1,
						y: 0,
					},
					{ id: "body", type: "action", plugin: "p", action: "body", config: {}, x: 2, y: 0 },
				],
				[
					{ id: "e1", from: "outer", to: "inner", port: "body" },
					{ id: "e2", from: "inner", to: "body", port: "body" },
				],
				"outer"
			)
			const compiler = new GraphCompiler()
			const program = compiler.compile(graph)

			// Both loops should produce separate LOOP_CHECK and LOOP_STEP instructions
			const loopChecks = program.instructions.filter((i) => i.op === OpCode.LOOP_CHECK)
			expect(loopChecks.length).toBe(2)
			// They should use different counter slots
			expect(loopChecks[0].arg0).not.toBe(loopChecks[1].arg0)
		})

		it("compiles for loop followed by action using 'next' port", () => {
			const graph = makeGraph(
				[
					{
						id: "for1",
						type: "for",
						variable: "i",
						start: { type: "literal", value: 0 },
						end: { type: "literal", value: 5 },
						step: { type: "literal", value: 1 },
						x: 0,
						y: 0,
					},
					{ id: "body", type: "action", plugin: "p", action: "body", config: {}, x: 1, y: 0 },
					{ id: "after", type: "action", plugin: "p", action: "after", config: {}, x: 2, y: 0 },
				],
				[
					{ id: "e1", from: "for1", to: "body", port: "body" },
					{ id: "e2", from: "for1", to: "after", port: "next" },
				],
				"for1"
			)
			const compiler = new GraphCompiler()
			const program = compiler.compile(graph)

			// HALT should be the last instruction
			expect(program.instructions[program.instructions.length - 1].op).toBe(OpCode.HALT)
			// after node should be compiled
			expect(program.instructions.some((i) => i.op === OpCode.EXEC && i.nodeId === "after")).toBe(true)
		})
	})

	describe("edge cases", () => {
		it("node with no outgoing edges halts", () => {
			const graph = makeGraph(
				[{ id: "a1", type: "action", plugin: "p", action: "a", config: {}, x: 0, y: 0 }],
				[],
				"a1"
			)
			const compiler = new GraphCompiler()
			const program = compiler.compile(graph)

			expect(program.instructions[program.instructions.length - 1].op).toBe(OpCode.HALT)
		})

		it("duplicate node visits are prevented", () => {
			// Create a diamond: a1 -> a2, a1 -> a3, a2 -> a4, a3 -> a4
			const graph = makeGraph(
				[
					{ id: "if1", type: "if", condition: { type: "literal", value: true }, x: 0, y: 0 },
					{ id: "a2", type: "action", plugin: "p", action: "b", config: {}, x: 1, y: 0 },
					{ id: "a3", type: "action", plugin: "p", action: "c", config: {}, x: 1, y: 1 },
					{ id: "a4", type: "action", plugin: "p", action: "d", config: {}, x: 2, y: 0 },
				],
				[
					{ id: "e1", from: "if1", to: "a2", port: "then" },
					{ id: "e2", from: "if1", to: "a3", port: "else" },
					{ id: "e3", from: "a2", to: "a4" },
					{ id: "e4", from: "a3", to: "a4" },
				],
				"if1"
			)
			const compiler = new GraphCompiler()
			const program = compiler.compile(graph)

			// a4 should appear at most once in EXEC instructions
			const a4Execs = program.instructions.filter((i) => i.op === OpCode.EXEC && i.nodeId === "a4")
			expect(a4Execs.length).toBeLessThanOrEqual(1)
		})
	})

	describe("wire map", () => {
		it("builds wireMap from dataWires", () => {
			const graph = makeGraph(
				[
					{ id: "a1", type: "action", plugin: "p", action: "a", config: {}, x: 0, y: 0 },
					{ id: "a2", type: "action", plugin: "p", action: "b", config: {}, x: 1, y: 0 },
				],
				[{ id: "e1", from: "a1", to: "a2" }],
				"a1"
			)
			const dataWires: AutomationDataWire[] = [
				{ id: "w1", fromNode: "a1", fromPort: "result", toNode: "a2", toPort: "input" },
			]
			const compiler = new GraphCompiler()
			const program = compiler.compile(graph, undefined, dataWires)

			expect(program.wireMap["a2:input"]).toEqual({ fromNodeId: "a1", fromPort: "result" })
		})

		it("produces empty wireMap when no dataWires", () => {
			const graph = makeGraph(
				[{ id: "a1", type: "action", plugin: "p", action: "a", config: {}, x: 0, y: 0 }],
				[],
				"a1"
			)
			const compiler = new GraphCompiler()
			const program = compiler.compile(graph)

			expect(program.wireMap).toEqual({})
		})

		it("handles multiple wires to same node", () => {
			const graph = makeGraph(
				[
					{ id: "a1", type: "action", plugin: "p", action: "a", config: {}, x: 0, y: 0 },
					{ id: "a2", type: "action", plugin: "p", action: "b", config: {}, x: 0, y: 1 },
					{ id: "a3", type: "action", plugin: "p", action: "c", config: {}, x: 1, y: 0 },
				],
				[
					{ id: "e1", from: "a1", to: "a3" },
					{ id: "e2", from: "a2", to: "a3" },
				],
				"a1"
			)
			const dataWires: AutomationDataWire[] = [
				{ id: "w1", fromNode: "a1", fromPort: "x", toNode: "a3", toPort: "inputA" },
				{ id: "w2", fromNode: "a2", fromPort: "y", toNode: "a3", toPort: "inputB" },
			]
			const compiler = new GraphCompiler()
			const program = compiler.compile(graph, undefined, dataWires)

			expect(program.wireMap["a3:inputA"]).toEqual({ fromNodeId: "a1", fromPort: "x" })
			expect(program.wireMap["a3:inputB"]).toEqual({ fromNodeId: "a2", fromPort: "y" })
		})
	})
})
