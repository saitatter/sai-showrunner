import type {
	AutomationGraph,
	GraphNode,
	GraphEdge,
	SubgraphDefinition,
	Expression,
} from "ShowRunner-schema"

// ─── Instruction Set ──────────────────────────────────────────────────────────

export enum OpCode {
	/** Execute an action node. arg0=nodeIndex in program.nodes */
	EXEC = 0,
	/** Unconditional jump. arg0=target instruction index */
	JUMP = 1,
	/** Jump if top of eval stack is truthy. arg0=target */
	JUMP_IF = 2,
	/** Jump if top of eval stack is falsy. arg0=target */
	JUMP_IF_NOT = 3,
	/** Evaluate expression, push result to eval stack. arg1=Expression */
	EVAL = 4,
	/** Pop eval stack → local variable. arg0=local slot index */
	STORE = 5,
	/** Push local variable → eval stack. arg0=local slot index */
	LOAD = 6,
	/** Initialize for-loop. arg0=counter slot, arg1=start expr, arg2=end expr */
	LOOP_INIT = 7,
	/** Check for-loop condition (counter < end). arg0=counter slot, arg1=end slot, arg2=exit target */
	LOOP_CHECK = 8,
	/** Increment loop counter. arg0=counter slot, arg1=step expr */
	LOOP_STEP = 9,
	/** Initialize forEach iterator. arg0=item slot, arg1=index slot, arg2=collection expr */
	ITER_INIT = 10,
	/** Advance iterator. arg0=item slot, arg1=index slot, arg2=exit target */
	ITER_NEXT = 11,
	/** Push call frame, jump to subgraph. arg0=subgraph index in program.subgraphs, arg1=input expressions */
	CALL = 12,
	/** Pop call frame, return to caller. arg1=output expressions */
	RET = 13,
	/** Yield control to event loop (prevents blocking) */
	YIELD = 14,
	/** End execution */
	HALT = 15,
}

export interface Instruction {
	op: OpCode
	/** Source node ID for debugger mapping */
	nodeId?: string
	arg0?: number
	arg1?: any
	arg2?: any
}

export interface CompiledSubgraph {
	id: string
	name: string
	entryPC: number
	paramSlots: number[]
	/** Parameter names in same order as paramSlots */
	paramNames: string[]
	outputExprs: Record<string, Expression>
}

export interface Program {
	instructions: Instruction[]
	/** Ordered node references for EXEC — maps nodeIndex to graph node */
	actionNodes: GraphNode[]
	/** Compiled subgraph lookup */
	subgraphs: CompiledSubgraph[]
	/** Total local slots needed */
	localSlotCount: number
	/** Maps slot index → variable name(s) for expression resolution */
	slotNames: string[]
}

// ─── Compiler ─────────────────────────────────────────────────────────────────

const DEFAULT_YIELD_INTERVAL = 64

export interface CompilerOptions {
	/** Insert YIELD every N instructions in loops (default 64) */
	yieldInterval?: number
	/** Maximum loop iterations safety cap (default 10000) */
	maxIterations?: number
}

export class GraphCompiler {
	private instructions: Instruction[] = []
	private actionNodes: GraphNode[] = []
	private localSlots = new Map<string, number>()
	private nextSlot = 0
	private loopExitStack: number[][] = [] // stack of [exitLabel] for break
	private loopHeaderStack: number[][] = [] // stack of [headerLabel] for continue
	private labels = new Map<number, number>() // label id → resolved instruction index
	private nextLabel = 0
	private pendingJumps: { instrIndex: number; labelId: number }[] = []
	private yieldInterval: number
	private maxIterations: number
	private edgeMap = new Map<string, GraphEdge[]>() // from nodeId → outgoing edges
	private nodeMap = new Map<string, GraphNode>()
	/** Maps nodeId → instruction index where it was first compiled (for merge points) */
	private nodePC = new Map<string, number>()

	constructor(private options: CompilerOptions = {}) {
		this.yieldInterval = options.yieldInterval ?? DEFAULT_YIELD_INTERVAL
		this.maxIterations = options.maxIterations ?? 10000
	}

	compile(graph: AutomationGraph, subgraphs?: SubgraphDefinition[]): Program {
		this.reset()
		this.buildMaps(graph.nodes, graph.edges)

		// Compile subgraphs first
		const compiledSubgraphs: CompiledSubgraph[] = []
		if (subgraphs) {
			for (const sg of subgraphs) {
				compiledSubgraphs.push(this.compileSubgraph(sg))
			}
		}

		// Compile main graph
		this.compileFromEntry(graph.entryNodeId)
		this.emit({ op: OpCode.HALT })

		// Resolve all jump labels
		this.resolveLabels()

		// Build slot→name reverse map
		const slotNames = new Array<string>(this.nextSlot).fill("")
		for (const [name, slot] of this.localSlots) {
			// Prefer user-facing names (no internal prefixes)
			if (!slotNames[slot] || slotNames[slot].includes(":")) {
				slotNames[slot] = name
			}
		}

		return {
			instructions: this.instructions,
			actionNodes: this.actionNodes,
			subgraphs: compiledSubgraphs,
			localSlotCount: this.nextSlot,
			slotNames,
		}
	}

	private reset() {
		this.instructions = []
		this.actionNodes = []
		this.localSlots = new Map()
		this.nextSlot = 0
		this.loopExitStack = []
		this.loopHeaderStack = []
		this.labels = new Map()
		this.nextLabel = 0
		this.pendingJumps = []
		this.edgeMap = new Map()
		this.nodeMap = new Map()
	}

	private buildMaps(nodes: GraphNode[], edges: GraphEdge[]) {
		for (const node of nodes) {
			this.nodeMap.set(node.id, node)
		}
		for (const edge of edges) {
			const list = this.edgeMap.get(edge.from) ?? []
			list.push(edge)
			this.edgeMap.set(edge.from, list)
		}
	}

	private compileFromEntry(entryNodeId: string) {
		const visited = new Set<string>()
		this.compileNode(entryNodeId, visited)
	}

	private compileNode(nodeId: string, visited: Set<string>) {
		if (visited.has(nodeId)) {
			// Merge point: node already compiled elsewhere, emit JUMP to its start
			const pc = this.nodePC.get(nodeId)
			if (pc != null) {
				this.instructions.push({ op: OpCode.JUMP, nodeId, arg0: pc })
			}
			return
		}
		visited.add(nodeId)

		const node = this.nodeMap.get(nodeId)
		if (!node) return

		// Record instruction index for this node (for merge point jumps)
		this.nodePC.set(nodeId, this.instructions.length)

		switch (node.type) {
			case "action":
				this.compileAction(node, visited)
				break
			case "if":
				this.compileIf(node, visited)
				break
			case "switch":
				this.compileSwitch(node, visited)
				break
			case "for":
				this.compileFor(node, visited)
				break
			case "forEach":
				this.compileForEach(node, visited)
				break
			case "while":
				this.compileWhile(node, visited)
				break
			case "break":
				this.compileBreak(node)
				break
			case "continue":
				this.compileContinue(node)
				break
			case "return":
				this.compileReturn(node)
				break
			case "subgraphCall":
				this.compileSubgraphCall(node, visited)
				break
		}
	}

	private compileAction(node: GraphNode, visited: Set<string>) {
		const idx = this.actionNodes.length
		this.actionNodes.push(node)
		this.emit({ op: OpCode.EXEC, nodeId: node.id, arg0: idx })

		// Follow default "out" edge
		const next = this.getEdgeTarget(node.id, undefined)
		if (next) this.compileNode(next, visited)
	}

	private compileIf(node: GraphNode, visited: Set<string>) {
		if (node.type !== "if") return
		const elseLabel = this.newLabel()
		const endLabel = this.newLabel()

		// Evaluate condition
		this.emit({ op: OpCode.EVAL, nodeId: node.id, arg1: node.condition })
		this.emitJumpToLabel(OpCode.JUMP_IF_NOT, elseLabel, node.id)

		// Then branch
		const thenTarget = this.getEdgeTarget(node.id, "then")
		if (thenTarget) this.compileNode(thenTarget, visited)
		this.emitJumpToLabel(OpCode.JUMP, endLabel, node.id)

		// Else branch
		this.placeLabel(elseLabel)
		const elseTarget = this.getEdgeTarget(node.id, "else")
		if (elseTarget) this.compileNode(elseTarget, visited)

		this.placeLabel(endLabel)

		// Continue after if
		const next = this.getEdgeTarget(node.id, "next")
		if (next) this.compileNode(next, visited)
	}

	private compileSwitch(node: GraphNode, visited: Set<string>) {
		if (node.type !== "switch") return
		const endLabel = this.newLabel()

		// Evaluate the switch expression once, store in a temp slot
		const switchSlot = this.allocSlot(node.id + ":switchVal")
		this.emit({ op: OpCode.EVAL, nodeId: node.id, arg1: node.expression })
		this.emit({ op: OpCode.STORE, nodeId: node.id, arg0: switchSlot })

		// Register the slot so it's accessible by variable name
		const switchVarName = `__switch_${node.id}`
		this.localSlots.set(switchVarName, switchSlot)

		for (const c of node.cases) {
			const skipLabel = this.newLabel()
			// Compare: switchVal == case value using a binary expression referencing the variable
			this.emit({
				op: OpCode.EVAL,
				nodeId: node.id,
				arg1: {
					type: "binary",
					op: "==",
					left: { type: "variable", name: switchVarName },
					right: { type: "literal", value: c.value },
				},
			})
			this.emitJumpToLabel(OpCode.JUMP_IF_NOT, skipLabel, node.id)

			// Case body
			const target = this.getEdgeTarget(node.id, c.port)
			if (target) this.compileNode(target, visited)
			this.emitJumpToLabel(OpCode.JUMP, endLabel, node.id)

			this.placeLabel(skipLabel)
		}

		// Default case
		const defaultTarget = this.getEdgeTarget(node.id, "default")
		if (defaultTarget) this.compileNode(defaultTarget, visited)

		this.placeLabel(endLabel)

		const next = this.getEdgeTarget(node.id, "next")
		if (next) this.compileNode(next, visited)
	}

	private compileFor(node: GraphNode, visited: Set<string>) {
		if (node.type !== "for") return
		const counterSlot = this.allocSlot(node.id + ":counter")
		const endSlot = this.allocSlot(node.id + ":end")
		const headerLabel = this.newLabel()
		const exitLabel = this.newLabel()

		// Init counter
		this.emit({ op: OpCode.EVAL, nodeId: node.id, arg1: node.start })
		this.emit({ op: OpCode.STORE, nodeId: node.id, arg0: counterSlot })
		// Store end value
		this.emit({ op: OpCode.EVAL, nodeId: node.id, arg1: node.end })
		this.emit({ op: OpCode.STORE, nodeId: node.id, arg0: endSlot })

		// Expose counter as local variable for body nodes
		this.localSlots.set(node.variable, counterSlot)

		this.placeLabel(headerLabel)
		// Check: counter < end
		this.emit({ op: OpCode.LOOP_CHECK, nodeId: node.id, arg0: counterSlot, arg1: endSlot, arg2: -1 })
		this.pendingJumps.push({ instrIndex: this.instructions.length - 1, labelId: exitLabel })

		// Body
		this.loopExitStack.push([exitLabel])
		this.loopHeaderStack.push([headerLabel])

		const bodyTarget = this.getEdgeTarget(node.id, "body")
		if (bodyTarget) this.compileNode(bodyTarget, visited)

		// Yield in loops
		this.emit({ op: OpCode.YIELD, nodeId: node.id })

		// Step
		this.emit({ op: OpCode.LOOP_STEP, nodeId: node.id, arg0: counterSlot, arg1: node.step })

		this.emitJumpToLabel(OpCode.JUMP, headerLabel, node.id)
		this.placeLabel(exitLabel)

		this.loopExitStack.pop()
		this.loopHeaderStack.pop()

		const next = this.getEdgeTarget(node.id, "next")
		if (next) this.compileNode(next, visited)
	}

	private compileForEach(node: GraphNode, visited: Set<string>) {
		if (node.type !== "forEach") return
		const itemSlot = this.allocSlot(node.id + ":item")
		const indexSlot = this.allocSlot(node.id + ":index")
		const collSlot = this.allocSlot(node.id + ":coll")
		const headerLabel = this.newLabel()
		const exitLabel = this.newLabel()

		// Evaluate and store collection
		this.emit({ op: OpCode.EVAL, nodeId: node.id, arg1: node.collection })
		this.emit({ op: OpCode.STORE, nodeId: node.id, arg0: collSlot })

		// Init index = 0
		this.emit({ op: OpCode.EVAL, nodeId: node.id, arg1: { type: "literal", value: 0 } })
		this.emit({ op: OpCode.STORE, nodeId: node.id, arg0: indexSlot })

		this.localSlots.set(node.variable, itemSlot)
		if (node.indexVariable) this.localSlots.set(node.indexVariable, indexSlot)

		this.placeLabel(headerLabel)
		// ITER_NEXT: check index < collection.length, load item
		this.emit({ op: OpCode.ITER_NEXT, nodeId: node.id, arg0: itemSlot, arg1: indexSlot, arg2: -1 })
		// Store collSlot reference for VM
		this.instructions[this.instructions.length - 1].arg2 = -1 // placeholder for exit
		this.pendingJumps.push({ instrIndex: this.instructions.length - 1, labelId: exitLabel })
		// VM needs collSlot — encode in a secondary way
		;(this.instructions[this.instructions.length - 1] as any).__collSlot = collSlot

		this.loopExitStack.push([exitLabel])
		this.loopHeaderStack.push([headerLabel])

		const bodyTarget = this.getEdgeTarget(node.id, "body")
		if (bodyTarget) this.compileNode(bodyTarget, visited)

		this.emit({ op: OpCode.YIELD, nodeId: node.id })

		// Increment index
		this.emit({
			op: OpCode.LOOP_STEP,
			nodeId: node.id,
			arg0: indexSlot,
			arg1: { type: "literal", value: 1 },
		})
		this.emitJumpToLabel(OpCode.JUMP, headerLabel, node.id)
		this.placeLabel(exitLabel)

		this.loopExitStack.pop()
		this.loopHeaderStack.pop()

		const next = this.getEdgeTarget(node.id, "next")
		if (next) this.compileNode(next, visited)
	}

	private compileWhile(node: GraphNode, visited: Set<string>) {
		if (node.type !== "while") return
		const headerLabel = this.newLabel()
		const exitLabel = this.newLabel()

		this.placeLabel(headerLabel)
		this.emit({ op: OpCode.EVAL, nodeId: node.id, arg1: node.condition })
		this.emitJumpToLabel(OpCode.JUMP_IF_NOT, exitLabel, node.id)

		this.loopExitStack.push([exitLabel])
		this.loopHeaderStack.push([headerLabel])

		const bodyTarget = this.getEdgeTarget(node.id, "body")
		if (bodyTarget) this.compileNode(bodyTarget, visited)

		this.emit({ op: OpCode.YIELD, nodeId: node.id })
		this.emitJumpToLabel(OpCode.JUMP, headerLabel, node.id)
		this.placeLabel(exitLabel)

		this.loopExitStack.pop()
		this.loopHeaderStack.pop()

		const next = this.getEdgeTarget(node.id, "next")
		if (next) this.compileNode(next, visited)
	}

	private compileBreak(node: GraphNode) {
		const exitLabels = this.loopExitStack[this.loopExitStack.length - 1]
		if (exitLabels) {
			this.emitJumpToLabel(OpCode.JUMP, exitLabels[0], node.id)
		}
	}

	private compileContinue(node: GraphNode) {
		const headerLabels = this.loopHeaderStack[this.loopHeaderStack.length - 1]
		if (headerLabels) {
			this.emitJumpToLabel(OpCode.JUMP, headerLabels[0], node.id)
		}
	}

	private compileReturn(node: GraphNode) {
		if (node.type !== "return") return
		this.emit({ op: OpCode.RET, nodeId: node.id, arg1: node.outputs })
	}

	private compileSubgraphCall(node: GraphNode, visited: Set<string>) {
		if (node.type !== "subgraphCall") return
		this.emit({ op: OpCode.CALL, nodeId: node.id, arg0: -1, arg1: node.inputs })
		// arg0 will be resolved to subgraph index at link time — store subgraphId for now
		;(this.instructions[this.instructions.length - 1] as any).__subgraphId = node.subgraphId

		const next = this.getEdgeTarget(node.id, undefined)
		if (next) this.compileNode(next, visited)
	}

	private compileSubgraph(sg: SubgraphDefinition): CompiledSubgraph {
		const entryPC = this.instructions.length
		// Build maps for subgraph nodes
		const prevEdgeMap = this.edgeMap
		const prevNodeMap = this.nodeMap
		this.edgeMap = new Map()
		this.nodeMap = new Map()
		this.buildMaps(sg.nodes, sg.edges)

		const paramSlots: number[] = []
		for (const p of sg.parameters) {
			paramSlots.push(this.allocSlot(`sg:${sg.id}:${p.name}`))
			this.localSlots.set(p.name, paramSlots[paramSlots.length - 1])
		}

		this.compileFromEntry(sg.entryNodeId)
		// Implicit return at end
		this.emit({ op: OpCode.RET, arg1: undefined })

		// Restore maps
		this.edgeMap = prevEdgeMap
		this.nodeMap = prevNodeMap

		return {
			id: sg.id,
			name: sg.name,
			entryPC,
			paramSlots,
			paramNames: sg.parameters.map((p) => p.name),
			outputExprs: {},
		}
	}

	// ─── Helpers ────────────────────────────────────────────────────────────────

	private emit(instr: Instruction) {
		this.instructions.push(instr)
	}

	private newLabel(): number {
		return this.nextLabel++
	}

	private placeLabel(labelId: number) {
		this.labels.set(labelId, this.instructions.length)
	}

	private emitJumpToLabel(op: OpCode, labelId: number, nodeId?: string) {
		const idx = this.instructions.length
		this.emit({ op, nodeId, arg0: -1 })
		this.pendingJumps.push({ instrIndex: idx, labelId })
	}

	private resolveLabels() {
		for (const { instrIndex, labelId } of this.pendingJumps) {
			const target = this.labels.get(labelId)
			if (target != null) {
				const instr = this.instructions[instrIndex]
				// For LOOP_CHECK and ITER_NEXT, exit target is in arg2
				if (instr.op === OpCode.LOOP_CHECK || instr.op === OpCode.ITER_NEXT) {
					instr.arg2 = target
				} else {
					instr.arg0 = target
				}
			}
		}

		// Resolve subgraph call indices
		for (const instr of this.instructions) {
			if (instr.op === OpCode.CALL && (instr as any).__subgraphId) {
				// Already handled by VM via subgraphId lookup
			}
		}
	}

	private allocSlot(key: string): number {
		if (this.localSlots.has(key)) return this.localSlots.get(key)!
		const slot = this.nextSlot++
		this.localSlots.set(key, slot)
		return slot
	}

	private getEdgeTarget(fromId: string, port: string | undefined): string | undefined {
		const edges = this.edgeMap.get(fromId)
		if (!edges) return undefined
		const match = edges.find((e) => (e.port ?? undefined) === port)
		return match?.to
	}
}
