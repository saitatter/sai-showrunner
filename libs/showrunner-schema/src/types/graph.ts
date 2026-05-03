// ─── Expression DSL ───────────────────────────────────────────────────────────

export type BinaryOp =
	| "=="
	| "!="
	| ">"
	| "<"
	| ">="
	| "<="
	| "&&"
	| "||"
	| "+"
	| "-"
	| "*"
	| "/"
	| "%"

export type UnaryOp = "!" | "-" | "typeof"

export type BuiltinFn =
	| "len"
	| "includes"
	| "startsWith"
	| "endsWith"
	| "toString"
	| "toNumber"
	| "toBoolean"
	| "floor"
	| "ceil"
	| "round"
	| "abs"
	| "min"
	| "max"
	| "keys"
	| "values"
	| "slice"
	| "concat"

export type Expression =
	| { type: "literal"; value: any }
	| { type: "variable"; name: string }
	| { type: "port"; nodeId: string; port: string }
	| { type: "binary"; op: BinaryOp; left: Expression; right: Expression }
	| { type: "unary"; op: UnaryOp; operand: Expression }
	| { type: "member"; object: Expression; property: string }
	| { type: "index"; object: Expression; index: Expression }
	| { type: "call"; fn: BuiltinFn; args: Expression[] }

// ─── Graph Node Types ─────────────────────────────────────────────────────────

export type GraphNodeType =
	| "action"
	| "if"
	| "switch"
	| "for"
	| "forEach"
	| "while"
	| "break"
	| "continue"
	| "return"
	| "subgraphCall"

export interface GraphNodeBase {
	id: string
	type: GraphNodeType
	x: number
	y: number
}

export interface ActionGraphNode extends GraphNodeBase {
	type: "action"
	plugin: string
	action: string
	config: any
	resultMapping?: Record<string, string>
}

export interface IfGraphNode extends GraphNodeBase {
	type: "if"
	condition: Expression
}

export interface SwitchGraphNode extends GraphNodeBase {
	type: "switch"
	expression: Expression
	cases: { value: any; port: string }[]
}

export interface ForGraphNode extends GraphNodeBase {
	type: "for"
	variable: string
	start: Expression
	end: Expression
	step: Expression
}

export interface ForEachGraphNode extends GraphNodeBase {
	type: "forEach"
	variable: string
	indexVariable?: string
	collection: Expression
}

export interface WhileGraphNode extends GraphNodeBase {
	type: "while"
	condition: Expression
	maxIterations?: number
}

export interface BreakGraphNode extends GraphNodeBase {
	type: "break"
}

export interface ContinueGraphNode extends GraphNodeBase {
	type: "continue"
}

export interface ReturnGraphNode extends GraphNodeBase {
	type: "return"
	outputs?: Record<string, Expression>
}

export interface SubgraphCallGraphNode extends GraphNodeBase {
	type: "subgraphCall"
	subgraphId: string
	inputs: Record<string, Expression>
}

export type GraphNode =
	| ActionGraphNode
	| IfGraphNode
	| SwitchGraphNode
	| ForGraphNode
	| ForEachGraphNode
	| WhileGraphNode
	| BreakGraphNode
	| ContinueGraphNode
	| ReturnGraphNode
	| SubgraphCallGraphNode

// ─── Execution Edges ──────────────────────────────────────────────────────────

export interface GraphEdge {
	id: string
	from: string
	to: string
	/** Port name: "then" | "else" | "body" | "next" | "case:N" | "default" | undefined (= default "out") */
	port?: string
}

export interface AutomationDataWire {
	id: string
	fromNode: string
	fromPort: string
	toNode: string
	toPort: string
}

// ─── Graph & Subgraph Definitions ────────────────────────────────────────────

export type SubgraphParamType = "string" | "number" | "boolean" | "array" | "object" | "any" | "color"

export interface SubgraphParam {
	name: string
	type: SubgraphParamType
	default?: any
	expression?: Expression
}

export interface SubgraphDefinition {
	id: string
	name: string
	parameters: SubgraphParam[]
	outputs: SubgraphParam[]
	nodes: GraphNode[]
	edges: GraphEdge[]
	dataWires?: AutomationDataWire[]
	entryNodeId: string
}

export interface AutomationGraph {
	nodes: GraphNode[]
	edges: GraphEdge[]
	entryNodeId: string
}
