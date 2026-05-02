/**
 * Pure helper functions for building renderable node/edge data from the automation model.
 * Extracted from NodeAutomationEdit.vue to reduce file size.
 */
import {
	ActionDefinition,
} from "ShowRunner-ui-core"
import {
	type ActionGraphNode,
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
	kind: "trigger" | "action" | "queue" | "stack" | "time" | "flow" | "floating" | "variable" | "if" | "switch" | "for" | "forEach" | "while" | "break" | "continue" | "return"
	title: string
	subtitle: string
	icon: string
	badge?: string
	missing?: boolean
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
	port?: string
	label?: string
	labelWidth?: number
	labelX?: number
	labelY?: number
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
	action: ActionGraphNode,
	pluginMap: Map<string, { actions: Record<string, ActionDefinition> }>
): { inputPorts: PortDef[]; outputPorts: PortDef[] } {
	const actionDef = pluginMap.get(action.plugin)?.actions?.[action.action]
	if (!actionDef) return { inputPorts: [], outputPorts: [] }

	const inputPorts = schemaToPorts(actionDef.config)
	const outputPorts = actionDef.type === "regular" ? schemaToPorts(actionDef.result) : []

	return { inputPorts, outputPorts }
}

function schemaToPorts(schema: unknown): PortDef[] {
	const inputPorts: PortDef[] = []
	if (schema && isObjectSchema(schema)) {
		for (const [key, propSchema] of Object.entries(schema.properties)) {
			if (inputPorts.length >= MAX_PORTS) break
			const label = (propSchema && typeof propSchema === "object" && "name" in propSchema && propSchema.name)
				? String(propSchema.name)
				: titleCase(key)
			inputPorts.push({ key, label, type: schemaTypeLabel(propSchema) })
		}
	}
	return inputPorts
}

export function extractConfigSummary(
	action: ActionGraphNode,
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

const QUEUE_ACTION_IDS = new Set(["addToQueue", "completeQueueItem", "cancelQueueItem", "clearQueue", "skip", "pause"])

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
	let inputPorts: PortDef[] | undefined
	let outputPorts: PortDef[] | undefined

	switch (gn.type) {
		case "action": {
			const action = gn as any
			const plugin = pluginMap.get(action.plugin)
			const actionDef = plugin?.actions?.[action.action]
			if (!actionDef) {
				return {
					id: gn.id,
					kind: "action",
					title: "Missing action",
					subtitle: `${action.plugin || "unknown"} / ${action.action || "unknown"}`,
					icon: "mdi mdi-alert-circle-outline",
					badge: "Missing",
					missing: true,
					x: action.x ?? 0,
					y: action.y ?? 0,
					configLines: [
						{ label: "plugin", value: action.plugin || "unknown" },
						{ label: "action", value: action.action || "unknown" },
					],
					height: computeNodeHeight([
						{ label: "plugin", value: action.plugin || "unknown" },
						{ label: "action", value: action.action || "unknown" },
					]),
				}
			}
			title = actionDef.name ?? titleCase(action.action)
			subtitle = `${plugin?.name ?? action.plugin} / ${action.action}`
			configLines = extractConfigSummary(action, pluginMap)
			const ports = extractPorts(action, pluginMap)
			inputPorts = ports.inputPorts
			outputPorts = ports.outputPorts
			if (action.plugin === "ShowRunner" && QUEUE_ACTION_IDS.has(action.action)) {
				return {
					id: gn.id,
					kind: "queue",
					title,
					subtitle,
					icon: actionDef.icon ?? "mdi mdi-tray-full",
					badge: "Queue",
					x: action.x ?? 0,
					y: action.y ?? 0,
					configLines,
					inputPorts,
					outputPorts,
					height: computeNodeHeight(configLines, inputPorts, outputPorts),
				}
			}
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
		inputPorts,
		outputPorts,
		height: computeNodeHeight(configLines, inputPorts, outputPorts),
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
		port: e.port,
	}))
	return { nodes, edges }
}

export function buildGraph(
	automation: AutomationConfig,
	pluginMap: Map<string, { actions: Record<string, ActionDefinition> }>,
	_getPreviewConfiguredDurationSeconds: (id: string) => number | undefined
) {
	if (!automation) return { nodes: [], edges: [] }
	const { nodes: graphNodes, edges: graphEdges } = buildGraphFromAutomationGraph(
		automation.graph ?? { nodes: [], edges: [], entryNodeId: "" },
		pluginMap
	)
	const triggerId = "trigger"
	const triggerNode: NodeData = {
		id: triggerId,
		kind: "trigger",
		title: getTriggerMissing(automation, pluginMap) ? "Missing trigger" : automation.trigger ? titleCase(automation.trigger) : "Start",
		subtitle: automation.plugin ? `${automation.plugin} / ${automation.trigger ?? "trigger"}` : "Entry point",
		icon: getTriggerMissing(automation, pluginMap) ? "mdi mdi-alert-circle-outline" : "mdi mdi-flash",
		badge: getTriggerMissing(automation, pluginMap) ? "Missing" : undefined,
		missing: getTriggerMissing(automation, pluginMap),
		x: 42,
		y: 88,
		configLines: getTriggerMissing(automation, pluginMap)
			? [
				{ label: "plugin", value: automation.plugin || "unknown" },
				{ label: "trigger", value: automation.trigger || "unknown" },
			]
			: undefined,
		outputPorts: getTriggerOutputPorts(automation, pluginMap),
		height: NODE_BASE_HEIGHT,
	}
	triggerNode.height = computeNodeHeight(triggerNode.configLines, undefined, triggerNode.outputPorts)
	const nodes = [triggerNode, ...graphNodes]
	const edges = [...graphEdges]
	if (automation.graph?.entryNodeId) {
		edges.push({ id: `${triggerId}:${automation.graph.entryNodeId}`, from: triggerId, to: automation.graph.entryNodeId })
	}
	return { nodes, edges }
}

function getTriggerMissing(
	automation: AutomationConfig,
	pluginMap: Map<string, { triggers?: Record<string, { context?: unknown }> }>
) {
	if (!automation.plugin || !automation.trigger) return false
	return !pluginMap.get(automation.plugin)?.triggers?.[automation.trigger]
}

function getTriggerOutputPorts(
	automation: AutomationConfig,
	pluginMap: Map<string, { triggers?: Record<string, { context?: unknown }> }>
): PortDef[] | undefined {
	if (!automation.plugin || !automation.trigger) return undefined
	const context = pluginMap.get(automation.plugin)?.triggers?.[automation.trigger]?.context
	if (!context || typeof context === "function") return undefined
	const ports = schemaToPorts(context)
	return ports.length ? ports : undefined
}

export function getNodeLane(node: NodeData): Pick<LaneData, "id" | "kind" | "label"> {
	if (node.id === "trigger") return { id: "main", kind: "main", label: "Main Flow" }
	if (node.kind === "if" || node.kind === "switch") return { id: "flow", kind: "flow", label: "Flow Branches" }
	if (node.kind === "queue") return { id: "queue", kind: "flow", label: "Queue Scheduler" }
	if (node.kind === "for" || node.kind === "forEach" || node.kind === "while") return { id: "time", kind: "time", label: "Loops" }
	if (node.kind === "break" || node.kind === "continue" || node.kind === "return") return { id: "flow", kind: "flow", label: "Control" }
	return { id: "main", kind: "main", label: "Main Flow" }
}
