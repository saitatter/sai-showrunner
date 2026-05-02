import { describe, it, expect } from "vitest"
import { evalExpression, type EvalContext } from "../expression"
import type { Expression } from "ShowRunner-schema"

function mkCtx(overrides: Partial<EvalContext> = {}): EvalContext {
	return {
		locals: overrides.locals ?? new Map(),
		contextState: overrides.contextState ?? {},
		nodeResults: overrides.nodeResults ?? new Map(),
	}
}

describe("evalExpression", () => {
	describe("literals", () => {
		it("returns number", () => {
			expect(evalExpression({ type: "literal", value: 42 }, mkCtx())).toBe(42)
		})
		it("returns string", () => {
			expect(evalExpression({ type: "literal", value: "hello" }, mkCtx())).toBe("hello")
		})
		it("returns boolean", () => {
			expect(evalExpression({ type: "literal", value: true }, mkCtx())).toBe(true)
		})
		it("returns null", () => {
			expect(evalExpression({ type: "literal", value: null }, mkCtx())).toBe(null)
		})
		it("returns array", () => {
			expect(evalExpression({ type: "literal", value: [1, 2, 3] }, mkCtx())).toEqual([1, 2, 3])
		})
	})

	describe("variables", () => {
		it("resolves local variable", () => {
			const locals = new Map([["x", 10]])
			expect(evalExpression({ type: "variable", name: "x" }, mkCtx({ locals }))).toBe(10)
		})
		it("resolves context state", () => {
			expect(evalExpression({ type: "variable", name: "msg" }, mkCtx({ contextState: { msg: "hi" } }))).toBe("hi")
		})
		it("locals take priority over contextState", () => {
			const locals = new Map([["x", "local"]])
			expect(evalExpression({ type: "variable", name: "x" }, mkCtx({ locals, contextState: { x: "ctx" } }))).toBe("local")
		})
		it("returns undefined for missing variable", () => {
			expect(evalExpression({ type: "variable", name: "missing" }, mkCtx())).toBeUndefined()
		})
	})

	describe("port references", () => {
		it("resolves node output port", () => {
			const nodeResults = new Map([["n1", { message: "hello" }]])
			expect(evalExpression({ type: "port", nodeId: "n1", port: "message" }, mkCtx({ nodeResults }))).toBe("hello")
		})
		it("returns undefined for missing node", () => {
			expect(evalExpression({ type: "port", nodeId: "nope", port: "x" }, mkCtx())).toBeUndefined()
		})
		it("returns undefined for missing port", () => {
			const nodeResults = new Map([["n1", { a: 1 }]])
			expect(evalExpression({ type: "port", nodeId: "n1", port: "b" }, mkCtx({ nodeResults }))).toBeUndefined()
		})
	})

	describe("binary operators", () => {
		const cases: [string, Expression, any][] = [
			["==", { type: "binary", op: "==", left: { type: "literal", value: 1 }, right: { type: "literal", value: 1 } }, true],
			["!= true", { type: "binary", op: "!=", left: { type: "literal", value: 1 }, right: { type: "literal", value: 2 } }, true],
			[">", { type: "binary", op: ">", left: { type: "literal", value: 5 }, right: { type: "literal", value: 3 } }, true],
			["<", { type: "binary", op: "<", left: { type: "literal", value: 2 }, right: { type: "literal", value: 7 } }, true],
			[">=", { type: "binary", op: ">=", left: { type: "literal", value: 5 }, right: { type: "literal", value: 5 } }, true],
			["<=", { type: "binary", op: "<=", left: { type: "literal", value: 3 }, right: { type: "literal", value: 5 } }, true],
			["&&", { type: "binary", op: "&&", left: { type: "literal", value: true }, right: { type: "literal", value: false } }, false],
			["||", { type: "binary", op: "||", left: { type: "literal", value: false }, right: { type: "literal", value: true } }, true],
			["+", { type: "binary", op: "+", left: { type: "literal", value: 3 }, right: { type: "literal", value: 4 } }, 7],
			["+ strings", { type: "binary", op: "+", left: { type: "literal", value: "a" }, right: { type: "literal", value: "b" } }, "ab"],
			["-", { type: "binary", op: "-", left: { type: "literal", value: 10 }, right: { type: "literal", value: 3 } }, 7],
			["*", { type: "binary", op: "*", left: { type: "literal", value: 4 }, right: { type: "literal", value: 5 } }, 20],
			["/", { type: "binary", op: "/", left: { type: "literal", value: 10 }, right: { type: "literal", value: 2 } }, 5],
			["/ by zero", { type: "binary", op: "/", left: { type: "literal", value: 10 }, right: { type: "literal", value: 0 } }, 0],
			["%", { type: "binary", op: "%", left: { type: "literal", value: 7 }, right: { type: "literal", value: 3 } }, 1],
			["% by zero", { type: "binary", op: "%", left: { type: "literal", value: 7 }, right: { type: "literal", value: 0 } }, 0],
		]
		for (const [label, expr, expected] of cases) {
			it(label, () => expect(evalExpression(expr, mkCtx())).toBe(expected))
		}
	})

	describe("unary operators", () => {
		it("!", () => {
			expect(evalExpression({ type: "unary", op: "!", operand: { type: "literal", value: false } }, mkCtx())).toBe(true)
		})
		it("- (negate)", () => {
			expect(evalExpression({ type: "unary", op: "-", operand: { type: "literal", value: 5 } }, mkCtx())).toBe(-5)
		})
		it("typeof", () => {
			expect(evalExpression({ type: "unary", op: "typeof", operand: { type: "literal", value: "hi" } }, mkCtx())).toBe("string")
		})
	})

	describe("member access", () => {
		it("accesses object property", () => {
			const ctx = mkCtx({ contextState: { obj: { foo: "bar" } } })
			const expr: Expression = { type: "member", object: { type: "variable", name: "obj" }, property: "foo" }
			expect(evalExpression(expr, ctx)).toBe("bar")
		})
		it("returns undefined on null object", () => {
			const expr: Expression = { type: "member", object: { type: "literal", value: null }, property: "x" }
			expect(evalExpression(expr, mkCtx())).toBeUndefined()
		})
	})

	describe("index access", () => {
		it("accesses array by index", () => {
			const ctx = mkCtx({ contextState: { arr: [10, 20, 30] } })
			const expr: Expression = { type: "index", object: { type: "variable", name: "arr" }, index: { type: "literal", value: 1 } }
			expect(evalExpression(expr, ctx)).toBe(20)
		})
		it("accesses object by dynamic key", () => {
			const ctx = mkCtx({ contextState: { obj: { a: 1, b: 2 } } })
			const expr: Expression = { type: "index", object: { type: "variable", name: "obj" }, index: { type: "literal", value: "b" } }
			expect(evalExpression(expr, ctx)).toBe(2)
		})
	})

	describe("builtin functions", () => {
		it("len of array", () => {
			const expr: Expression = { type: "call", fn: "len", args: [{ type: "literal", value: [1, 2, 3] }] }
			expect(evalExpression(expr, mkCtx())).toBe(3)
		})
		it("len of string", () => {
			const expr: Expression = { type: "call", fn: "len", args: [{ type: "literal", value: "hello" }] }
			expect(evalExpression(expr, mkCtx())).toBe(5)
		})
		it("includes array", () => {
			const expr: Expression = { type: "call", fn: "includes", args: [{ type: "literal", value: [1, 2, 3] }, { type: "literal", value: 2 }] }
			expect(evalExpression(expr, mkCtx())).toBe(true)
		})
		it("includes string", () => {
			const expr: Expression = { type: "call", fn: "includes", args: [{ type: "literal", value: "hello world" }, { type: "literal", value: "world" }] }
			expect(evalExpression(expr, mkCtx())).toBe(true)
		})
		it("startsWith", () => {
			const expr: Expression = { type: "call", fn: "startsWith", args: [{ type: "literal", value: "hello" }, { type: "literal", value: "hel" }] }
			expect(evalExpression(expr, mkCtx())).toBe(true)
		})
		it("endsWith", () => {
			const expr: Expression = { type: "call", fn: "endsWith", args: [{ type: "literal", value: "hello" }, { type: "literal", value: "llo" }] }
			expect(evalExpression(expr, mkCtx())).toBe(true)
		})
		it("toString", () => {
			const expr: Expression = { type: "call", fn: "toString", args: [{ type: "literal", value: 42 }] }
			expect(evalExpression(expr, mkCtx())).toBe("42")
		})
		it("toNumber", () => {
			const expr: Expression = { type: "call", fn: "toNumber", args: [{ type: "literal", value: "3.14" }] }
			expect(evalExpression(expr, mkCtx())).toBeCloseTo(3.14)
		})
		it("toNumber returns 0 for NaN", () => {
			const expr: Expression = { type: "call", fn: "toNumber", args: [{ type: "literal", value: "abc" }] }
			expect(evalExpression(expr, mkCtx())).toBe(0)
		})
		it("toBoolean", () => {
			expect(evalExpression({ type: "call", fn: "toBoolean", args: [{ type: "literal", value: 0 }] }, mkCtx())).toBe(false)
			expect(evalExpression({ type: "call", fn: "toBoolean", args: [{ type: "literal", value: "hi" }] }, mkCtx())).toBe(true)
		})
		it("floor", () => {
			expect(evalExpression({ type: "call", fn: "floor", args: [{ type: "literal", value: 3.7 }] }, mkCtx())).toBe(3)
		})
		it("ceil", () => {
			expect(evalExpression({ type: "call", fn: "ceil", args: [{ type: "literal", value: 3.2 }] }, mkCtx())).toBe(4)
		})
		it("round", () => {
			expect(evalExpression({ type: "call", fn: "round", args: [{ type: "literal", value: 3.5 }] }, mkCtx())).toBe(4)
		})
		it("abs", () => {
			expect(evalExpression({ type: "call", fn: "abs", args: [{ type: "literal", value: -7 }] }, mkCtx())).toBe(7)
		})
		it("min", () => {
			expect(evalExpression({ type: "call", fn: "min", args: [{ type: "literal", value: 3 }, { type: "literal", value: 1 }, { type: "literal", value: 5 }] }, mkCtx())).toBe(1)
		})
		it("max", () => {
			expect(evalExpression({ type: "call", fn: "max", args: [{ type: "literal", value: 3 }, { type: "literal", value: 1 }, { type: "literal", value: 5 }] }, mkCtx())).toBe(5)
		})
		it("keys", () => {
			const expr: Expression = { type: "call", fn: "keys", args: [{ type: "literal", value: { a: 1, b: 2 } }] }
			expect(evalExpression(expr, mkCtx())).toEqual(["a", "b"])
		})
		it("values", () => {
			const expr: Expression = { type: "call", fn: "values", args: [{ type: "literal", value: { a: 1, b: 2 } }] }
			expect(evalExpression(expr, mkCtx())).toEqual([1, 2])
		})
		it("slice array", () => {
			const expr: Expression = { type: "call", fn: "slice", args: [{ type: "literal", value: [1, 2, 3, 4] }, { type: "literal", value: 1 }, { type: "literal", value: 3 }] }
			expect(evalExpression(expr, mkCtx())).toEqual([2, 3])
		})
		it("slice string", () => {
			const expr: Expression = { type: "call", fn: "slice", args: [{ type: "literal", value: "hello" }, { type: "literal", value: 1 }, { type: "literal", value: 4 }] }
			expect(evalExpression(expr, mkCtx())).toBe("ell")
		})
		it("concat arrays", () => {
			const expr: Expression = { type: "call", fn: "concat", args: [{ type: "literal", value: [1, 2] }, { type: "literal", value: [3, 4] }] }
			expect(evalExpression(expr, mkCtx())).toEqual([1, 2, 3, 4])
		})
		it("concat strings", () => {
			const expr: Expression = { type: "call", fn: "concat", args: [{ type: "literal", value: "foo" }, { type: "literal", value: "bar" }] }
			expect(evalExpression(expr, mkCtx())).toBe("foobar")
		})
	})

	describe("nested expressions", () => {
		it("complex: (x + 1) * 2 == 10", () => {
			const locals = new Map([["x", 4]])
			const expr: Expression = {
				type: "binary",
				op: "==",
				left: {
					type: "binary",
					op: "*",
					left: { type: "binary", op: "+", left: { type: "variable", name: "x" }, right: { type: "literal", value: 1 } },
					right: { type: "literal", value: 2 },
				},
				right: { type: "literal", value: 10 },
			}
			expect(evalExpression(expr, mkCtx({ locals }))).toBe(true)
		})

		it("call with nested expression: len(slice(arr, 0, 2))", () => {
			const ctx = mkCtx({ contextState: { arr: [1, 2, 3, 4, 5] } })
			const expr: Expression = {
				type: "call",
				fn: "len",
				args: [{
					type: "call",
					fn: "slice",
					args: [
						{ type: "variable", name: "arr" },
						{ type: "literal", value: 0 },
						{ type: "literal", value: 2 },
					],
				}],
			}
			expect(evalExpression(expr, ctx)).toBe(2)
		})
	})
})
