import type { Ref } from "vue"
import { nanoid } from "nanoid"
import type { AutomationGraph, Expression, GraphNode, GraphNodeType } from "showrunner-schema"
import type { NodePosition } from "./useNodeCanvas"
import { isTerminalControlFlowNode } from "./automation-graph-editing"

interface PendingFlowConnection {
	fromNode: string
	fromPort?: string
	canvasPoint: NodePosition
}

interface UseControlFlowNodesOptions {
	getContextMenuCanvasPoint: () => NodePosition | undefined
	pendingFlowConnection: Ref<PendingFlowConnection | null>
	ensureGraph: () => AutomationGraph
	connectFlowToNode: (fromNode: string, fromPort: string | undefined, toNode: string, isTerminal?: boolean) => void
	closeContextMenu: () => void
	commitUndo: () => void
}

export function useControlFlowNodes(options: UseControlFlowNodesOptions) {
	const {
		getContextMenuCanvasPoint,
		pendingFlowConnection,
		ensureGraph,
		connectFlowToNode,
		closeContextMenu,
		commitUndo,
	} = options

	function addControlFlowNode(type: GraphNodeType) {
		const canvasPoint = getContextMenuCanvasPoint() ?? { x: 100, y: 200 }
		const id = nanoid()
		const graph = ensureGraph()

		let newNode: GraphNode
		switch (type) {
			case "if":
				newNode = { id, type: "if", x: canvasPoint.x, y: canvasPoint.y, condition: { type: "literal", value: true } }
				break
			case "switch":
				newNode = { id, type: "switch", x: canvasPoint.x, y: canvasPoint.y, expression: { type: "literal", value: "" }, cases: [{ value: "case1", port: "case:0" }] }
				break
			case "for":
				newNode = { id, type: "for", x: canvasPoint.x, y: canvasPoint.y, variable: "i", start: { type: "literal", value: 0 }, end: { type: "literal", value: 10 }, step: { type: "literal", value: 1 } }
				break
			case "forEach":
				newNode = { id, type: "forEach", x: canvasPoint.x, y: canvasPoint.y, variable: "item", collection: { type: "literal", value: [] } }
				break
			case "while":
				newNode = { id, type: "while", x: canvasPoint.x, y: canvasPoint.y, condition: { type: "literal", value: true }, maxIterations: 1000 }
				break
			case "break":
				newNode = { id, type: "break", x: canvasPoint.x, y: canvasPoint.y }
				break
			case "continue":
				newNode = { id, type: "continue", x: canvasPoint.x, y: canvasPoint.y }
				break
			case "return":
				newNode = { id, type: "return", x: canvasPoint.x, y: canvasPoint.y }
				break
			default:
				return
		}

		graph.nodes.push(newNode)

		if (pendingFlowConnection.value) {
			connectFlowToNode(pendingFlowConnection.value.fromNode, pendingFlowConnection.value.fromPort, id, isTerminalControlFlowNode(type))
		} else if (graph.nodes.length === 1) {
			graph.entryNodeId = id
		}

		closeContextMenu()
		commitUndo()
	}

	function expressionMode(expr: Expression | undefined) {
		if (!expr) return "true"
		if (expr.type === "literal" && expr.value === false) return "false"
		if (expr.type === "literal") return "true"
		if (expr.type === "binary" && expr.op === "==" && expr.left.type === "variable") return "equals"
		if (expr.type === "variable") return "variable"
		return "variable"
	}

	function expressionVariable(expr: Expression | undefined) {
		if (!expr) return ""
		if (expr.type === "variable") return expr.name
		if (expr.type === "binary" && expr.left.type === "variable") return expr.left.name
		return ""
	}

	function expressionCompareValue(expr: Expression | undefined) {
		if (expr?.type === "binary" && expr.right.type === "literal") return String(expr.right.value ?? "")
		return ""
	}

	function expressionValidationMessage(expr: Expression | undefined): string | undefined {
		if (!expr) return "Expression is empty."
		if (expr.type === "variable") return validateVariableName(expr.name)
		if (expr.type === "binary") {
			return expressionValidationMessage(expr.left) || expressionValidationMessage(expr.right)
		}
		if (expr.type === "call" && expr.args.some((arg) => expressionValidationMessage(arg))) {
			return "One function argument is invalid."
		}
		return undefined
	}

	function literalNumber(expr: Expression | undefined, fallback = 0) {
		return expr?.type === "literal" && Number.isFinite(Number(expr.value)) ? Number(expr.value) : fallback
	}

	function setControlExpressionMode(node: GraphNode, key: string, mode: string) {
		const next = getControlExpressionForMode(mode, expressionVariable((node as any)[key]), expressionCompareValue((node as any)[key]))
		;(node as any)[key] = next
		commitUndo()
	}

	function setControlExpressionVariable(node: GraphNode, key: string, variable: string) {
		const clean = variable.trim()
		const current = (node as any)[key] as Expression | undefined
		if (expressionMode(current) === "equals") {
			;(node as any)[key] = {
				type: "binary",
				op: "==",
				left: { type: "variable", name: clean },
				right: { type: "literal", value: expressionCompareValue(current) },
			}
		} else {
			;(node as any)[key] = clean ? { type: "variable", name: clean } : { type: "literal", value: true }
		}
		commitUndo()
	}

	function setControlExpressionCompareValue(node: GraphNode, key: string, value: string) {
		const variable = expressionVariable((node as any)[key]) || "value"
		;(node as any)[key] = {
			type: "binary",
			op: "==",
			left: { type: "variable", name: variable },
			right: { type: "literal", value },
		}
		commitUndo()
	}

	function setControlString(node: GraphNode, key: string, value: string) {
		;(node as any)[key] = value.trim() || key
		commitUndo()
	}

	function setControlNumber(node: GraphNode, key: string, value: number) {
		;(node as any)[key] = Number.isFinite(value) ? value : 1
		commitUndo()
	}

	function setControlLiteralNumber(node: GraphNode, key: string, value: number) {
		;(node as any)[key] = { type: "literal", value: Number.isFinite(value) ? value : 0 }
		commitUndo()
	}

	function setSwitchCaseValue(node: Extract<GraphNode, { type: "switch" }>, index: number, value: string) {
		if (!node.cases[index]) return
		node.cases[index].value = value
		commitUndo()
	}

	function addSwitchCase(node: Extract<GraphNode, { type: "switch" }>) {
		node.cases.push({ value: `case${node.cases.length + 1}`, port: `case:${node.cases.length}` })
		commitUndo()
	}

	function deleteSwitchCase(node: Extract<GraphNode, { type: "switch" }>, index: number) {
		node.cases.splice(index, 1)
		commitUndo()
	}

	return {
		addControlFlowNode,
		expressionMode,
		expressionVariable,
		expressionCompareValue,
		expressionValidationMessage,
		literalNumber,
		setControlExpressionMode,
		setControlExpressionVariable,
		setControlExpressionCompareValue,
		setControlString,
		setControlNumber,
		setControlLiteralNumber,
		setSwitchCaseValue,
		addSwitchCase,
		deleteSwitchCase,
	}
}

function validateVariableName(name: string) {
	const clean = String(name || "").trim()
	if (!clean) return "Variable name is required."
	if (clean.includes("(") || clean.includes(")")) return "Use the builder controls for function calls."
	if (!/^[a-zA-Z_$][\w$]*(\.[a-zA-Z_$][\w$]*|\[\d+\])*$/.test(clean)) {
		return "Use variable, nested.path, or items[0] format."
	}
	return undefined
}

function getControlExpressionForMode(mode: string, variable: string, compareValue: string): Expression {
	if (mode === "false") return { type: "literal", value: false }
	if (mode === "variable") return { type: "variable", name: variable || "value" }
	if (mode === "equals") {
		return {
			type: "binary",
			op: "==",
			left: { type: "variable", name: variable || "value" },
			right: { type: "literal", value: compareValue },
		}
	}
	return { type: "literal", value: true }
}
