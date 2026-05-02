import type { Expression, GraphNode } from "ShowRunner-schema"
import { OpCode, type Instruction, type IterNextArgs, type Program } from "./compiler"
import { evalExpression, type EvalContext } from "./expression"
import type { ExecutionDebugger } from "../queue-system/resolvers"
import { PluginManager } from "../plugins/plugin-manager"
import { deserializeSchema } from "../util/ipc-schema"

export interface GraphVMOptions {
	/** Maximum loop iterations before forced abort (default 10000) */
	maxIterations?: number
	/** Maximum subgraph recursion depth (default 32) */
	maxCallDepth?: number
}

interface CallFrame {
	returnPC: number
	localSnapshot: any[]
	callNodeId?: string
}

export type VMCompletion = "complete" | "aborted" | "error"

/**
 * Executes a compiled Program. Supports branching, loops, subgraph calls,
 * and real-time debugger hooks for UI visualization.
 */
export class GraphVM {
	private pc = 0
	private stack: any[] = []
	private locals: any[] = []
	private callStack: CallFrame[] = []
	private iterationCounters = new Map<string, number>()
	private nodeResults = new Map<string, Record<string, any>>()
	private aborted = false
	private maxIterations: number
	private maxCallDepth: number
	private localSlotsByName = new Map<string, number>()

	constructor(
		private program: Program,
		private context: { contextState: Record<string, any> },
		private dbg?: ExecutionDebugger,
		private abortSignal?: AbortSignal,
		options?: GraphVMOptions
	) {
		this.maxIterations = options?.maxIterations ?? 10000
		this.maxCallDepth = options?.maxCallDepth ?? 32
		this.locals = new Array(program.localSlotCount).fill(undefined)
		for (let i = 0; i < program.slotNames.length; i++) {
			const name = program.slotNames[i]
			if (name) this.localSlotsByName.set(name, i)
		}
	}

	/**
	 * Run the program to completion. Returns "complete", "aborted", or "error".
	 */
	async execute(): Promise<VMCompletion> {
		this.dbg?.sequenceStarted()
		try {
			while (this.pc < this.program.instructions.length) {
				if (this.aborted || this.abortSignal?.aborted) {
					this.dbg?.sequenceEnded()
					return "aborted"
				}

				const instr = this.program.instructions[this.pc]
				const advance = await this.step(instr)
				if (advance) this.pc++
			}
			this.dbg?.sequenceEnded()
			return "complete"
		} catch (err) {
			this.dbg?.logError?.(err instanceof Error ? err.message : String(err))
			this.dbg?.sequenceEnded()
			return "error"
		}
	}

	/** Abort execution from outside */
	abort() {
		this.aborted = true
	}

	/** Get results map (for data wire resolution after execution) */
	getNodeResults(): Map<string, Record<string, any>> {
		return this.nodeResults
	}

	private async step(instr: Instruction): Promise<boolean> {
		switch (instr.op) {
			case OpCode.EXEC:
				await this.execAction(instr)
				return true

			case OpCode.JUMP:
				this.pc = instr.arg0!
				return false

			case OpCode.JUMP_IF:
				if (this.stack.pop()) {
					this.pc = instr.arg0!
					return false
				}
				return true

			case OpCode.JUMP_IF_NOT:
				if (!this.stack.pop()) {
					this.pc = instr.arg0!
					return false
				}
				return true

			case OpCode.EVAL:
				this.stack.push(this.evalExpr(instr.arg1))
				return true

			case OpCode.STORE:
				this.locals[instr.arg0!] = this.stack.pop()
				return true

			case OpCode.LOAD:
				this.stack.push(this.locals[instr.arg0!])
				return true

			case OpCode.LOOP_INIT:
				// Not used directly — for/forEach use EVAL+STORE
				return true

			case OpCode.LOOP_CHECK: {
				const counter = this.locals[instr.arg0!]
				const end = this.locals[instr.arg1!]
				this.checkIterationLimit(instr.nodeId)
				if (counter >= end) {
					this.pc = instr.arg2! // jump to exit
					return false
				}
				return true
			}

			case OpCode.LOOP_STEP: {
				const current = Number(this.locals[instr.arg0!])
				const step = Number(this.evalExpr(instr.arg1))
				if (!Number.isFinite(current) || !Number.isFinite(step)) {
					throw new Error(`Loop step must be numeric at node ${instr.nodeId ?? "unknown"}`)
				}
				this.locals[instr.arg0!] = current + step
				return true
			}

			case OpCode.ITER_NEXT: {
				const itemSlot = instr.arg0!
				const { indexSlot, collSlot } = instr.arg1 as IterNextArgs
				const collection = this.locals[collSlot]
				const index = this.locals[indexSlot]

				this.checkIterationLimit(instr.nodeId)

				if (!Array.isArray(collection) || index >= collection.length) {
					this.pc = instr.arg2! // jump to exit
					return false
				}
				this.locals[itemSlot] = collection[index]
				return true
			}

			case OpCode.CALL:
				this.execCall(instr)
				return false // pc is set by call

			case OpCode.RET:
				this.execReturn(instr)
				return false // pc is set by return

			case OpCode.YIELD:
				await this.yieldToEventLoop()
				return true

			case OpCode.HALT:
				this.pc = this.program.instructions.length // end
				return false

			default:
				return true
		}
	}

	private async execAction(instr: Instruction) {
		const node = this.program.actionNodes[instr.arg0!]
		if (!node || node.type !== "action") return

		this.dbg?.markStart(node.id)
		try {
			// Resolve data wire inputs via nodeResults
			const resolvedConfig = this.resolveActionConfig(node)

			// Invoke via action registry
			const actionDef = PluginManager.getInstance().getAction(node.plugin, node.action)
			if (!actionDef || actionDef.type !== "regular") {
				throw new Error(`Unknown action: ${node.plugin}:${node.action}`)
			}

			const deserialized = await deserializeSchema(actionDef.configSchema, resolvedConfig)
			const result = await actionDef.invoke(deserialized, this.context, this.abortSignal)

			this.dbg?.logResult(node.id, result)

			// Store result
			if (result != null) {
				if (typeof result === "object") {
					this.nodeResults.set(node.id, result)
				} else {
					this.nodeResults.set(node.id, { _result: result })
				}
			}

			// Result mapping to context
			if (node.resultMapping) {
				for (const key in node.resultMapping) {
					this.context.contextState[node.resultMapping[key]] = result?.[key]
				}
			}
		} catch (err) {
			this.dbg?.logError(node.id, err)
			throw err
		} finally {
			this.dbg?.markEnd(node.id)
		}
	}

	private resolveActionConfig(node: GraphNode & { type: "action" }): any {
		const config = node.config ?? {}
		const wireMap = this.program.wireMap
		if (!wireMap || Object.keys(wireMap).length === 0) return config

		// Deep clone config and substitute wired inputs
		const resolved = structuredClone(config)

		const prefix = `${node.id}:`
		for (const [wireKey, source] of Object.entries(wireMap)) {
			if (!wireKey.startsWith(prefix)) continue
			const toPort = wireKey.slice(prefix.length)
			if (!toPort) continue

			const sourceResult = this.nodeResults.get(source.fromNodeId)
			setPathValue(resolved, toPort, getPathValue(sourceResult, source.fromPort))
		}

		return resolved
	}

	private execCall(instr: Instruction) {
		if (this.callStack.length >= this.maxCallDepth) {
			throw new Error(`Max call depth (${this.maxCallDepth}) exceeded`)
		}

		const subgraphIndex = instr.arg0!
		const sg = this.program.subgraphs[subgraphIndex]
		if (!sg) throw new Error(`Subgraph not found at index: ${subgraphIndex}`)

		// Push frame
		this.callStack.push({
			returnPC: this.pc + 1,
			localSnapshot: [...this.locals],
			callNodeId: instr.nodeId,
		})

		// Set parameter values from inputs — map by name for reliable binding
		const inputs = instr.arg1 as Record<string, Expression> | undefined
		if (inputs) {
			for (let i = 0; i < sg.paramNames.length; i++) {
				const paramName = sg.paramNames[i]
				if (paramName && inputs[paramName]) {
					this.locals[sg.paramSlots[i]] = this.evalExpr(inputs[paramName])
				}
			}
		}

		this.pc = sg.entryPC
	}

	private execReturn(instr: Instruction) {
		const frame = this.callStack.pop()
		if (!frame) {
			// Top-level return = halt
			this.pc = this.program.instructions.length
			return
		}

		const outputs: Record<string, any> = {}
		const outputExprs = instr.arg1 as Record<string, Expression> | undefined
		for (const key of Object.keys(outputExprs ?? {})) {
			outputs[key] = this.evalExpr(outputExprs?.[key])
		}

		// Restore locals
		this.locals = frame.localSnapshot
		if (frame.callNodeId) {
			this.nodeResults.set(frame.callNodeId, outputs)
		}
		this.pc = frame.returnPC
	}

	private evalExpr(expr: Expression | undefined): any {
		if (!expr) return undefined
		const ctx: EvalContext = {
			localValues: this.locals,
			localSlotsByName: this.localSlotsByName,
			contextState: this.context.contextState,
			nodeResults: this.nodeResults,
		}
		return evalExpression(expr, ctx)
	}

	private checkIterationLimit(nodeId?: string) {
		const key = nodeId ?? "__global"
		const count = (this.iterationCounters.get(key) ?? 0) + 1
		this.iterationCounters.set(key, count)
		if (count > this.maxIterations) {
			throw new Error(`Loop iteration limit (${this.maxIterations}) exceeded at node ${nodeId}`)
		}
	}

	private async yieldToEventLoop() {
		await new Promise<void>((resolve) => {
			if (typeof setImmediate !== "undefined") {
				setImmediate(resolve)
			} else {
				setTimeout(resolve, 0)
			}
		})
	}
}

function getPathValue(source: any, path: string) {
	if (source == null) return undefined
	const parts = parsePath(path)
	let cursor = source
	for (const part of parts) {
		if (cursor == null) return undefined
		if (isUnsafePathPart(part)) return undefined
		cursor = cursor[part as keyof typeof cursor]
	}
	return cursor
}

function setPathValue(target: Record<string, any>, path: string, value: any) {
	const parts = parsePath(path)
	if (parts.length === 0) return

	let cursor: any = target
	for (let i = 0; i < parts.length - 1; i++) {
		const part = parts[i]
		if (isUnsafePathPart(part)) return
		const nextPart = parts[i + 1]
		if (cursor[part] == null || typeof cursor[part] !== "object") {
			cursor[part] = typeof nextPart === "number" ? [] : {}
		}
		cursor = cursor[part]
	}
	const lastPart = parts[parts.length - 1]
	if (isUnsafePathPart(lastPart)) return
	cursor[lastPart] = value
}

function parsePath(path: string): Array<string | number> {
	const parts: Array<string | number> = []
	for (const match of path.matchAll(/([^.[\]]+)|\[(\d+)\]/g)) {
		if (match[1]) parts.push(match[1])
		else if (match[2]) parts.push(Number(match[2]))
	}
	return parts
}

function isUnsafePathPart(part: string | number): boolean {
	return part === "__proto__" || part === "constructor" || part === "prototype"
}
