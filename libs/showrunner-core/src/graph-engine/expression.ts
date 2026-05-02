import type { Expression, BuiltinFn } from "ShowRunner-schema"

export interface EvalContext {
	/** Local variables (loop counters, subgraph params) */
	locals?: Map<string, any>
	/** VM local slot values; used to avoid rebuilding a locals Map per expression. */
	localValues?: readonly any[]
	/** Local slot lookup by variable name. */
	localSlotsByName?: ReadonlyMap<string, number>
	/** Context state from trigger / upstream */
	contextState: Record<string, any>
	/** Node output results for port references */
	nodeResults: Map<string, Record<string, any>>
}

/**
 * Evaluates an Expression AST against the given context.
 * Safe: no eval(), no prototype access, no arbitrary code execution.
 */
export function evalExpression(expr: Expression, ctx: EvalContext): any {
	switch (expr.type) {
		case "literal":
			return expr.value

		case "variable": {
			const slot = ctx.localSlotsByName?.get(expr.name)
			if (slot != null && ctx.localValues && ctx.localValues[slot] !== undefined) return ctx.localValues[slot]
			if (ctx.locals?.has(expr.name)) return ctx.locals.get(expr.name)
			if (expr.name in ctx.contextState) return ctx.contextState[expr.name]
			return undefined
		}

		case "port": {
			const result = ctx.nodeResults.get(expr.nodeId)
			if (result == null) return undefined
			return result[expr.port]
		}

		case "binary":
			return evalBinary(expr.op, evalExpression(expr.left, ctx), evalExpression(expr.right, ctx))

		case "unary":
			return evalUnary(expr.op, evalExpression(expr.operand, ctx))

		case "member": {
			const obj = evalExpression(expr.object, ctx)
			if (obj == null) return undefined
			return obj[expr.property]
		}

		case "index": {
			const obj = evalExpression(expr.object, ctx)
			const idx = evalExpression(expr.index, ctx)
			if (obj == null) return undefined
			return obj[idx]
		}

		case "call":
			return evalBuiltin(expr.fn, expr.args.map((a) => evalExpression(a, ctx)))
	}
}

function evalBinary(op: string, left: any, right: any): any {
	switch (op) {
		case "==":
			return left === right
		case "!=":
			return left !== right
		case ">":
			return left > right
		case "<":
			return left < right
		case ">=":
			return left >= right
		case "<=":
			return left <= right
		case "&&":
			return left && right
		case "||":
			return left || right
		case "+":
			return left + right
		case "-":
			return left - right
		case "*":
			return left * right
		case "/":
			if (right === 0) return NaN
			return left / right
		case "%":
			if (right === 0) return NaN
			return left % right
		default:
			return undefined
	}
}

function evalUnary(op: string, operand: any): any {
	switch (op) {
		case "!":
			return !operand
		case "-":
			return -operand
		case "typeof":
			return typeof operand
		default:
			return undefined
	}
}

function evalBuiltin(fn: BuiltinFn, args: any[]): any {
	switch (fn) {
		case "len":
			return args[0]?.length ?? 0
		case "includes":
			if (Array.isArray(args[0])) return args[0].includes(args[1])
			if (typeof args[0] === "string") return args[0].includes(args[1])
			return false
		case "startsWith":
			return typeof args[0] === "string" ? args[0].startsWith(args[1] ?? "") : false
		case "endsWith":
			return typeof args[0] === "string" ? args[0].endsWith(args[1] ?? "") : false
		case "toString":
			return String(args[0] ?? "")
		case "toNumber": {
			const n = Number(args[0])
			return Number.isFinite(n) ? n : 0
		}
		case "toBoolean":
			return Boolean(args[0])
		case "floor":
			return Math.floor(Number(args[0]) || 0)
		case "ceil":
			return Math.ceil(Number(args[0]) || 0)
		case "round":
			return Math.round(Number(args[0]) || 0)
		case "abs":
			return Math.abs(Number(args[0]) || 0)
		case "min": {
			const numbers = args.map(Number).filter(Number.isFinite)
			return numbers.length > 0 ? Math.min(...numbers) : 0
		}
		case "max": {
			const numbers = args.map(Number).filter(Number.isFinite)
			return numbers.length > 0 ? Math.max(...numbers) : 0
		}
		case "keys":
			if (args[0] != null && typeof args[0] === "object") return Object.keys(args[0])
			return []
		case "values":
			if (args[0] != null && typeof args[0] === "object") return Object.values(args[0])
			return []
		case "slice": {
			const target = args[0]
			if (Array.isArray(target) || typeof target === "string") {
				return target.slice(Number(args[1]) || 0, args[2] != null ? Number(args[2]) : undefined)
			}
			return target
		}
		case "concat": {
			if (Array.isArray(args[0])) return args[0].concat(args[1] ?? [])
			if (typeof args[0] === "string") return args[0] + String(args[1] ?? "")
			return args[0]
		}
		default:
			return undefined
	}
}
