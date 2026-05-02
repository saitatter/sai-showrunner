/**
 * Pure helper functions for building renderable node/edge data from the automation model.
 * Extracted from NodeAutomationEdit.vue to reduce file size.
 */
import {
	ActionDefinition,
} from "ShowRunner-ui-core"
import {
	AnyAction,
	ActionStack,
	FloatingSequence,
	Sequence,
	isActionStack,
	isFlowAction,
	isTimeAction,
	isObjectSchema,
	type AutomationGraph,
	type GraphNode,
	type GraphNodeType,
	type AutomationConfig,
} from "ShowRunner-schema"
import type { PortDef } from "./usePortConnections"

// ─── Shared Types ─────────────────────────────────────────────────────────────

export interface ConfigLine {
	label: string
	value: string
}

export interface NodeData {
	id: string
	kind: "trigger" | "action" | "stack" | "time" | "flow" | "floating" | "variable" | "if" | "switch" | "for" | "forEach" | "while" | "break" | "continue" | "return"
	title: string
	subtitle: string
	icon: string
	badge?: string
	path?: string
	configLines?: ConfigLine[]
	inputPorts?: PortDef[]
	outputPorts?: PortDef[]
	height: number
	width?: number
	x: number
	y: number
}

export interface EdgeData {
	id: string
	from: string
	to: string
	path: string
}

export interface LaneData {
	id: string
	kind: "main" | "floating" | "stack" | "time" | "flow"
	label: string
	width: number
	height: number
	x: number
	y: number
}

// ─── Constants ────────────────────────────────────────────────────────────────

export const NODE_WIDTH = 220
export const NODE_BASE_HEIGHT = 74
export const CONFIG_LINE_HEIGHT = 20
export const PORT_LINE_HEIGHT = 18
export const MAX_CONFIG_LINES = 4
export const MAX_PORTS = 8
export const H_GAP = 285
export const V_GAP = 128

// ─── Pure Functions ───────────────────────────────────────────────────────────

export function computeNodeHeight(configLines?: ConfigLine[], inputPorts?: PortDef[], outputPorts?: PortDef[]): number {
	let h = NODE_BASE_HEIGHT
	if (configLines && configLines.length > 0) h += configLines.length * CONFIG_LINE_HEIGHT + 4
	const portCount = Math.max(inputPorts?.length ?? 0, outputPorts?.length ?? 0)
	if (portCount > 0) h += portCount * PORT_LINE_HEIGHT + 8
	return h
}

export function summarizeConfigValue(value: unknown): string {
	if (value == null) return "—"
	if (typeof value === "string") return value.length > 28 ? value.slice(0, 25) + "…" : value || "—"
	if (typeof value === "number" || typeof value === "boolean") return String(value)
	if (Array.isArray(value)) return `[${value.length} item${value.length === 1 ? "" : "s"}]`
	if (typeof value === "object") {
		const keys = Object.keys(value)
		if (keys.length === 0) return "{}"
		return `{${keys.slice(0, 2).join(", ")}${keys.length > 2 ? "…" : ""}}`
	}
	return String(value)
}

export function schemaTypeLabel(schema: unknown): string {
	if (!schema || typeof schema !== "object") return "any"
	if ("type" in schema) {
		const t = (schema as any).type
		if (t === String) return "str"
		if (t === Number) return "num"
		if (t === Boolean) return "bool"
		if (t === Object) return "obj"
		if (t === Array) return "list"
	}
	return "any"
}

export function titleCase(value: string) {
	return value
		.replace(/[-_]/g, " ")
		.replace(/([a-z])([A-Z])/g, "$1 $2")
		.replace(/\b\w/g, (letter) => letter.toUpperCase())
}

export function formatSeconds(value: number) {
	return `${Number(value.toFixed(2))}s`
}

export function extractPorts(
	action: AnyAction,
	pluginMap: Map<string, { actions: Record<string, ActionDefinition> }>
): { inputPorts: PortDef[]; outputPorts: PortDef[] } {
	const actionDef = pluginMap.get(action.plugin)?.actions?.[action.action]
	if (!actionDef) return { inputPorts: [], outputPorts: [] }

	const inputPorts: PortDef[] = []
	const schema = actionDef.config
	if (schema && isObjectSchema(schema)) {
		for (const [key, propSchema] of Object.entries(schema.properties)) {
			if (inputPorts.length >= MAX_PORTS) break
			const label = (propSchema && typeof propSchema === "object" && "name" in propSchema && propSchema.name)
				? String(propSchema.name)
				: titleCase(key)
			inputPorts.push({ key, label, type: schemaTypeLabel(propSchema) })
		}
	}

	const outputPorts: PortDef[] = []
	if (actionDef.type === "regular" && actionDef.result && isObjectSchema(actionDef.result)) {
		for (const [key, propSchema] of Object.entries(actionDef.result.properties)) {
			if (outputPorts.length >= MAX_PORTS) break
			const label = (propSchema && typeof propSchema === "object" && "name" in propSchema && propSchema.name)
				? String(propSchema.name)
				: titleCase(key)
			outputPorts.push({ key, label, type: schemaTypeLabel(propSchema) })
		}
	}

	return { inputPorts, outputPorts }
}

export function extractConfigSummary(
	action: AnyAction,
	pluginMap: Map<string, { actions: Record<string, ActionDefinition> }>
): ConfigLine[] {
	const actionDef = pluginMap.get(action.plugin)?.actions?.[action.action]
	if (!actionDef) return []

	const lines: ConfigLine[] = []
	const schema = actionDef.config
	let totalProps = 0
	if (schema && isObjectSchema(schema) && action.config) {
		const entries = Object.entries(schema.properties)
		totalProps = entries.length
		for (const [key, propSchema] of entries) {
			if (lines.length >= MAX_CONFIG_LINES) break
			const value = (action.config as Record<string, unknown>)[key]
			if (value == null && !(propSchema as any).required) continue
			const label = ("name" in propSchema && propSchema.name) ? String(propSchema.name) : titleCase(key)
			lines.push({ label, value: summarizeConfigValue(value) })
		}
	}

	if (isFlowAction(action) && actionDef.type === "flow") {
		const flowDef = actionDef as any
		action.subFlows.forEach((flow, i) => {
			if (lines.length >= MAX_CONFIG_LINES) return
			let branchLabel = `Branch ${i + 1}`
			if (flowDef.flowConfig && isObjectSchema(flowDef.flowConfig) && flow.config) {
				const firstProp = Object.entries(flowDef.flowConfig.properties)[0]
				if (firstProp) {
					const val = (flow.config as Record<string, unknown>)[firstProp[0]]
					if (val != null) branchLabel += `: ${summarizeConfigValue(val)}`
				}
			}
			lines.push({ label: "↳", value: branchLabel })
		})
	}

	if (isTimeAction(action)) {
		action.offsets.forEach((offset) => {
			if (lines.length >= MAX_CONFIG_LINES) return
			lines.push({ label: "↳", value: `+${offset.offset}s → ${offset.actions.length} action${offset.actions.length === 1 ? "" : "s"}` })
		})
	}

	if (totalProps > lines.length) {
		lines.push({ label: "…", value: `+${totalProps - lines.length} more` })
	}

	return lines
}

// ─── Graph Node Rendering ─────────────────────────────────────────────────────

export const GRAPH_NODE_INFO: Record<GraphNodeType, { icon: string; kind: NodeData["kind"]; label: string }> = {
	action: { icon: "mdi mdi-play", kind: "action", label: "Action" },
	if: { icon: "mdi mdi-source-branch", kind: "if", label: "If" },
	switch: { icon: "mdi mdi-source-fork", kind: "switch", label: "Switch" },
	for: { icon: "mdi mdi-repeat", kind: "for", label: "For Loop" },
	forEach: { icon: "mdi mdi-format-list-numbered", kind: "forEach", label: "For Each" },
	while: { icon: "mdi mdi-sync", kind: "while", label: "While" },
	break: { icon: "mdi mdi-debug-step-out", kind: "break", label: "Break" },
	continue: { icon: "mdi mdi-skip-next", kind: "continue", label: "Continue" },
	return: { icon: "mdi mdi-keyboard-return", kind: "return", label: "Return" },
	subgraphCall: { icon: "mdi mdi-function", kind: "action", label: "Subgraph" },
}

export function summarizeExpression(expr: any): string {
	if (!expr) return "—"
	switch (expr.type) {
		case "literal": return JSON.stringify(expr.value)?.slice(0, 20) ?? "—"
		case "variable": return `$${expr.name}`
		case "port": return `${expr.nodeId}.${expr.port}`
		case "binary": return `${summarizeExpression(expr.left)} ${expr.op} ${summarizeExpression(expr.right)}`
		case "unary": return `${expr.op}${summarizeExpression(expr.operand)}`
		case "call": return `${expr.fn}(…)`
		case "member": return `${summarizeExpression(expr.object)}.${expr.property}`
		case "index": return `${summarizeExpression(expr.object)}[…]`
		default: return "expr"
	}
}

export function graphNodeToNodeData(
	gn: GraphNode,
	pluginMap: Map<string, { actions: Record<string, ActionDefinition> }>
): NodeData {
	const info = GRAPH_NODE_INFO[gn.type]
	let title = info.label
	let subtitle = ""
	let configLines: ConfigLine[] | undefined
	let outputPorts: PortDef[] | undefined

	switch (gn.type) {
		case "action": {
			title = titleCase((gn as any).action)
			subtitle = `${(gn as any).plugin} / ${(gn as any).action}`
			configLines = extractConfigSummary(gn as any, pluginMap)
			break
		}
		case "if":
			subtitle = "condition"
			configLines = [{ label: "when", value: summarizeExpression((gn as any).condition) }]
			outputPorts = [
				{ key: "then", label: "then", type: "flow" },
				{ key: "else", label: "else", type: "flow" },
			]
			break
		case "switch":
			subtitle = `${(gn as any).cases.length} case${(gn as any).cases.length === 1 ? "" : "s"}`
			configLines = [{ label: "expr", value: summarizeExpression((gn as any).expression) }]
			outputPorts = [
				...(gn as any).cases.map((c: any) => ({ key: c.port, label: String(c.value), type: "flow" as const })),
				{ key: "default", label: "default", type: "flow" as const },
			]
			break
		case "for":
			subtitle = `${(gn as any).variable}`
			configLines = [
				{ label: "from", value: summarizeExpression((gn as any).start) },
				{ label: "to", value: summarizeExpression((gn as any).end) },
			]
			outputPorts = [
				{ key: "body", label: "body", type: "flow" },
				{ key: "next", label: "done", type: "flow" },
			]
			break
		case "forEach":
			subtitle = `${(gn as any).variable} in collection`
			configLines = [{ label: "of", value: summarizeExpression((gn as any).collection) }]
			outputPorts = [
				{ key: "body", label: "body", type: "flow" },
				{ key: "next", label: "done", type: "flow" },
			]
			break
		case "while":
			subtitle = `max ${(gn as any).maxIterations ?? 10000}`
			configLines = [{ label: "while", value: summarizeExpression((gn as any).condition) }]
			outputPorts = [
				{ key: "body", label: "body", type: "flow" },
				{ key: "next", label: "done", type: "flow" },
			]
			break
		case "break":
			subtitle = "exit loop"
			break
		case "continue":
			subtitle = "next iteration"
			break
		case "return":
			subtitle = "end execution"
			break
		case "subgraphCall":
			title = "Call Subgraph"
			subtitle = (gn as any).subgraphId
			break
	}

	return {
		id: gn.id,
		kind: info.kind,
		title,
		subtitle,
		icon: info.icon,
		x: (gn as any).x ?? 0,
		y: (gn as any).y ?? 0,
		configLines,
		outputPorts,
		height: computeNodeHeight(configLines, undefined, outputPorts),
	}
}

export function buildGraphFromAutomationGraph(
	automationGraph: AutomationGraph,
	pluginMap: Map<string, { actions: Record<string, ActionDefinition> }>
) {
	const nodes: NodeData[] = automationGraph.nodes.map((gn) => graphNodeToNodeData(gn, pluginMap))
	const edges: Omit<EdgeData, "path">[] = automationGraph.edges.map((e) => ({
		id: e.id,
		from: e.from,
		to: e.to,
	}))
	return { nodes, edges }
}

export function buildGraph(
	automation: AutomationConfig,
	pluginMap: Map<string, { actions: Record<string, ActionDefinition> }>,
	getPreviewConfiguredDurationSeconds: (id: string) => number | undefined
) {
	if (!automation) return { nodes: [], edges: [] }
	if (automation.graph) {
		const { nodes: graphNodes, edges: graphEdges } = buildGraphFromAutomationGraph(automation.graph, pluginMap)
		const triggerId = "trigger"
		const triggerNode: NodeData = {
			id: triggerId,
			kind: "trigger",
			title: automation.trigger ? titleCase(automation.trigger) : "Start",
			subtitle: automation.plugin ? `${automation.plugin} trigger` : "Entry point",
			icon: "mdi mdi-flash",
			x: 42,
			y: 88,
			height: NODE_BASE_HEIGHT,
		}
		const nodes = [triggerNode, ...graphNodes]
		const edges = [...graphEdges]
		if (automation.graph.entryNodeId) {
			edges.push({ id: `${triggerId}:${automation.graph.entryNodeId}`, from: triggerId, to: automation.graph.entryNodeId })
		}
		return { nodes, edges }
	}

	const nodes: NodeData[] = []
	const edges: Omit<EdgeData, "path">[] = []

	const triggerId = "trigger"
	nodes.push({
		id: triggerId,
		kind: "trigger",
		title: automation.trigger ? titleCase(automation.trigger) : "Start",
		subtitle: automation.plugin ? `${automation.plugin} trigger` : "Entry point",
		icon: "mdi mdi-flash",
		x: 42,
		y: 88,
		height: NODE_BASE_HEIGHT,
	})

	if (automation.sequence) {
		const mainNodes = addSequence(nodes, edges, automation.sequence, "sequence", 1, 0, "Main", pluginMap, getPreviewConfiguredDurationSeconds)
		if (mainNodes[0]) edges.push({ id: `${triggerId}:${mainNodes[0]}`, from: triggerId, to: mainNodes[0] })
	}

	automation.floatingSequences?.forEach((sequence, index) => {
		const floatingId = sequence.id || `floating-${index}`
		nodes.push({
			id: floatingId,
			kind: "floating",
			title: `Floating ${index + 1}`,
			subtitle: `${sequence.actions.length} action${sequence.actions.length === 1 ? "" : "s"}`,
			icon: "mdi mdi-vector-polyline",
			badge: "free",
			x: 42,
			y: 280 + index * V_GAP,
			path: `floatingSequences[${index}]`,
			height: NODE_BASE_HEIGHT,
		})
		const childNodes = addSequence(nodes, edges, sequence, `floatingSequences[${index}]`, 1, index + 2, `Floating ${index + 1}`, pluginMap, getPreviewConfiguredDurationSeconds)
		if (childNodes[0]) edges.push({ id: `${floatingId}:${childNodes[0]}`, from: floatingId, to: childNodes[0] })
	})

	return { nodes, edges }
}

function addSequence(
	nodes: NodeData[],
	edges: Omit<EdgeData, "path">[],
	sequence: Sequence | FloatingSequence,
	path: string,
	column: number,
	row: number,
	group: string,
	pluginMap: Map<string, { actions: Record<string, ActionDefinition> }>,
	getPreviewConfiguredDurationSeconds: (id: string) => number | undefined
) {
	const ids: string[] = []
	sequence.actions.forEach((action, index) => {
		const node = createNode(action, `${path}.actions[${index}]`, column + index, row, group, pluginMap, getPreviewConfiguredDurationSeconds)
		nodes.push(node)
		ids.push(node.id)

		if (index > 0) {
			edges.push({ id: `${ids[index - 1]}:${node.id}`, from: ids[index - 1], to: node.id })
		}

		if (isActionStack(action)) {
			action.stack.forEach((stackAction, stackIndex) => {
				const child = createNode(stackAction, `${node.path}.stack[${stackIndex}]`, column + index, row + stackIndex + 1, "Stack", pluginMap, getPreviewConfiguredDurationSeconds)
				nodes.push(child)
				edges.push({ id: `${node.id}:${child.id}`, from: node.id, to: child.id })
			})
		}

		if (isTimeAction(action)) {
			action.offsets.forEach((offset, offsetIndex) => {
				const children = addSequence(
					nodes,
					edges,
					offset,
					`${node.path}.offsets[${offsetIndex}]`,
					column + index + 1,
					row + offsetIndex + 1,
					`+${offset.offset}s`,
					pluginMap,
					getPreviewConfiguredDurationSeconds
				)
				if (children[0]) edges.push({ id: `${node.id}:${children[0]}`, from: node.id, to: children[0] })
			})
		}

		if (isFlowAction(action)) {
			action.subFlows.forEach((flow, flowIndex) => {
				const children = addSequence(
					nodes,
					edges,
					flow,
					`${node.path}.subFlows[${flowIndex}]`,
					column + index + 1,
					row + flowIndex + 1,
					`Flow ${flowIndex + 1}`,
					pluginMap,
					getPreviewConfiguredDurationSeconds
				)
				if (children[0]) edges.push({ id: `${node.id}:${children[0]}`, from: node.id, to: children[0] })
			})
		}
	})
	return ids
}

function createNode(
	action: AnyAction | ActionStack,
	path: string,
	column: number,
	row: number,
	group: string,
	pluginMap: Map<string, { actions: Record<string, ActionDefinition> }>,
	getPreviewConfiguredDurationSeconds: (id: string) => number | undefined
): NodeData {
	if (isActionStack(action)) {
		const stackCount = action.stack.length
		return {
			id: action.id,
			kind: "stack",
			title: "Action Stack",
			subtitle: `${stackCount} parallel action${stackCount === 1 ? "" : "s"}`,
			icon: "mdi mdi-layers-triple",
			badge: `${group} stack`,
			x: 42 + column * H_GAP,
			y: 88 + row * V_GAP,
			path,
			height: NODE_BASE_HEIGHT,
		}
	}

	const timingSummary = getTimingSummary(action, getPreviewConfiguredDurationSeconds)
	const flowSummary = getFlowSummary(action)
	const configLines = extractConfigSummary(action, pluginMap)
	const { inputPorts, outputPorts } = extractPorts(action, pluginMap)

	return {
		id: action.id,
		kind: isFlowAction(action) ? "flow" : isTimeAction(action) ? "time" : "action",
		title: titleCase(action.action),
		subtitle: [action.plugin, action.action, timingSummary, flowSummary].filter(Boolean).join(" / "),
		icon: isFlowAction(action) ? "mdi mdi-source-branch" : isTimeAction(action) ? "mdi mdi-timer-outline" : "mdi mdi-play",
		badge: getNodeBadge(action, group),
		x: 42 + column * H_GAP,
		y: 88 + row * V_GAP,
		path,
		configLines,
		inputPorts: inputPorts.length > 0 ? inputPorts : undefined,
		outputPorts: outputPorts.length > 0 ? outputPorts : undefined,
		height: computeNodeHeight(configLines, inputPorts, outputPorts),
	}
}

function getNodeBadge(action: AnyAction, group: string) {
	if (isTimeAction(action)) return `${group} time`
	if (isFlowAction(action)) return `${group} flow`
	return group
}

function getTimingSummary(action: AnyAction, getPreviewConfiguredDurationSeconds: (id: string) => number | undefined) {
	if (!isTimeAction(action)) return undefined
	const offsets = action.offsets.length
	const duration = getPreviewConfiguredDurationSeconds(action.id)
	const parts = [`${offsets} offset${offsets === 1 ? "" : "s"}`]
	if (duration) parts.unshift(formatSeconds(duration))
	return parts.join(", ")
}

function getFlowSummary(action: AnyAction) {
	if (!isFlowAction(action)) return undefined
	const branches = action.subFlows.length
	return `${branches} branch${branches === 1 ? "" : "es"}`
}

export function getNodeLane(node: NodeData): Pick<LaneData, "id" | "kind" | "label"> {
	if (node.id === "trigger") return { id: "main", kind: "main", label: "Main Flow" }
	if (node.path?.includes(".stack[")) return { id: "stack", kind: "stack", label: "Stacked Actions" }
	if (node.path?.includes(".offsets[")) return { id: "time", kind: "time", label: "Time Offsets" }
	if (node.path?.includes(".subFlows[")) return { id: "flow", kind: "flow", label: "Flow Branches" }
	if (node.path?.startsWith("floatingSequences")) return { id: "floating", kind: "floating", label: "Floating Sequences" }
	return { id: "main", kind: "main", label: "Main Flow" }
}
