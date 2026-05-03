<template>
	<div class="automation-edit-page">
		<div v-if="recoveryIssues.length" class="automation-edit-page__recovery">
			<div>
				<p class="automation-edit-page__eyebrow">Recovery</p>
				<h2>Automation graph needs repair</h2>
				<p>
					This automation contains invalid graph references. Repair it before opening the node editor to avoid a blank
					canvas.
				</p>
			</div>
			<ul>
				<li v-for="issue in recoveryIssues" :key="issue">{{ issue }}</li>
			</ul>
			<div class="automation-edit-page__actions">
				<button type="button" @click="repairGraph">Repair graph</button>
				<button type="button" @click="rawJsonOpen = !rawJsonOpen">{{ rawJsonOpen ? "Hide raw JSON" : "Open raw JSON" }}</button>
				<button type="button" @click="duplicateBackup">Duplicate backup</button>
			</div>
			<textarea v-if="rawJsonOpen" readonly :value="rawJson" @focus="$event.target.select()" />
		</div>
		<div v-else-if="renderError" class="automation-edit-page__error">
			<strong>Automation editor failed</strong>
			<code>{{ renderError }}</code>
			<small>{{ debugSummary }}</small>
		</div>
		<node-automation-edit v-else v-model="safeModel" v-model:view="safeView" />
	</div>
</template>

<script setup lang="ts">
import { AutomationConfig, AutomationDataWire, AutomationGraph, AutomationVariableNode, GraphNode, SubgraphDefinition } from "ShowRunner-schema"
import { AutomationResourceView, useAppFeedback, useDocumentId, useResourceStore } from "ShowRunner-ui-core"
import { computed, onErrorCaptured, ref, toRaw, useModel } from "vue"
import NodeAutomationEdit from "./NodeAutomationEdit.vue"

const props = defineProps<{
	modelValue: AutomationConfig
	view: AutomationResourceView
}>()

const view = useModel(props, "view")
const model = useModel(props, "modelValue")
const renderError = ref("")
const feedback = useAppFeedback("Automation")
const resourceStore = useResourceStore()
const documentId = useDocumentId()
const rawJsonOpen = ref(false)

const safeModel = computed({
	get() {
		model.value ??= { name: "", graph: { nodes: [], edges: [], entryNodeId: "" }, subgraphs: [], dataWires: [], variableNodes: [] }
		model.value.graph ??= { nodes: [], edges: [], entryNodeId: "" }
		model.value.subgraphs ??= []
		model.value.dataWires ??= []
		model.value.variableNodes ??= []
		return model.value
	},
	set(value: AutomationConfig) {
		model.value = value
	},
})

const safeView = computed({
	get() {
		view.value ??= { automationView: { panState: { zoomX: 4, zoomY: 1, panX: 0, panY: 0, panning: false } } }
		view.value.automationView ??= {
			panState: {
				zoomX: 4,
				zoomY: 1,
				panX: 0,
				panY: 0,
				panning: false,
			},
		}
		return view.value
	},
	set(value: AutomationResourceView) {
		view.value = value
	},
})

const debugSummary = computed(() =>
	JSON.stringify({
		name: safeModel.value.name,
		hasGraph: !!safeModel.value.graph,
		graphNodeCount: safeModel.value.graph?.nodes?.length ?? 0,
		graphEdgeCount: safeModel.value.graph?.edges?.length ?? 0,
		entryNodeId: safeModel.value.graph?.entryNodeId ?? "",
		dataWireCount: safeModel.value.dataWires?.length ?? 0,
		variableNodeCount: safeModel.value.variableNodes?.length ?? 0,
		hasView: !!safeView.value,
		hasAutomationView: !!safeView.value.automationView,
		nodePositionCount: Object.keys((safeView.value as any).nodePositions ?? {}).length,
		nodeSizeCount: Object.keys((safeView.value as any).nodeSizes ?? {}).length,
		nodeView: (safeView.value as any).nodeView ?? null,
	})
)

const recoveryIssues = computed(() => validateAutomationGraph(safeModel.value))
const rawJson = computed(() => JSON.stringify(safeModel.value, null, "\t"))

function repairGraph() {
	const repaired = repairAutomation(safeModel.value)
	model.value = repaired
	renderError.value = ""
	rawJsonOpen.value = false
	feedback.warn("Automation graph repaired", "Review the graph before saving.")
}

async function duplicateBackup() {
	try {
		const backupName = `${safeModel.value.name || documentId.value || "Automation"} Backup`
		const backupId = await resourceStore.createResource("Automation", backupName)
		if (!backupId) throw new Error("Could not create backup automation.")
		await resourceStore.setResourceConfig("Automation", backupId, {
			...cloneAutomationConfig(safeModel.value),
			name: backupName,
		})
		feedback.success("Automation backup created", backupName)
	} catch (error) {
		feedback.error("Failed to duplicate automation backup", error)
	}
}

onErrorCaptured((error, instance, info) => {
	renderError.value = error instanceof Error ? error.stack || error.message : String(error)
	feedback.error("Automation editor failed", error)
	feedback.debug("Automation editor failure context", {
		error,
		info,
		instance,
		debug: JSON.parse(debugSummary.value),
	})
	return false
})

const VALID_NODE_TYPES = new Set(["action", "if", "switch", "for", "forEach", "while", "break", "continue", "return", "subgraphCall"])
const VALID_VARIABLE_TYPES = new Set(["string", "number", "boolean", "color"])

function validateAutomationGraph(config: AutomationConfig): string[] {
	const issues: string[] = []
	const graph = config.graph
	if (!graph || !Array.isArray(graph.nodes) || !Array.isArray(graph.edges)) {
		return ["Automation graph is missing or malformed."]
	}

	const nodeIds = new Set<string>()
	for (const node of graph.nodes) {
		if (!node || typeof node.id !== "string" || !node.id.trim()) {
			issues.push("A graph node is missing an id.")
			continue
		}
		if (nodeIds.has(node.id)) issues.push(`Duplicate node id: ${node.id}`)
		nodeIds.add(node.id)
		if (!VALID_NODE_TYPES.has(String(node.type))) issues.push(`Unsupported node type on ${node.id}: ${String(node.type)}`)
	}

	if (graph.entryNodeId && !nodeIds.has(graph.entryNodeId)) issues.push(`Entry node does not exist: ${graph.entryNodeId}`)

	for (const edge of graph.edges) {
		if (!edge || typeof edge.id !== "string" || !edge.id.trim()) issues.push("A graph edge is missing an id.")
		if (!nodeIds.has(edge?.from)) issues.push(`Edge ${edge?.id || "(missing id)"} starts at missing node: ${edge?.from || "(empty)"}`)
		if (!nodeIds.has(edge?.to)) issues.push(`Edge ${edge?.id || "(missing id)"} ends at missing node: ${edge?.to || "(empty)"}`)
	}

	const dataWireSourceIds = new Set(nodeIds)
	dataWireSourceIds.add("trigger")
	for (const wire of config.dataWires ?? []) {
		if (!wire || typeof wire.id !== "string" || !wire.id.trim()) issues.push("A data wire is missing an id.")
		if (!dataWireSourceIds.has(wire?.fromNode)) issues.push(`Data wire ${wire?.id || "(missing id)"} starts at missing node: ${wire?.fromNode || "(empty)"}`)
		if (!nodeIds.has(wire?.toNode)) issues.push(`Data wire ${wire?.id || "(missing id)"} ends at missing node: ${wire?.toNode || "(empty)"}`)
		if (!wire?.fromPort || !wire?.toPort) issues.push(`Data wire ${wire?.id || "(missing id)"} is missing a port.`)
	}

	for (const variable of config.variableNodes ?? []) {
		if (!variable?.id || !variable?.name) issues.push("A variable node is missing an id or name.")
		if (!VALID_VARIABLE_TYPES.has(String(variable?.type))) issues.push(`Variable ${variable?.name || variable?.id || "(unnamed)"} has an unsupported type.`)
	}

	for (const subgraph of config.subgraphs ?? []) {
		if (!subgraph?.id || !Array.isArray(subgraph.nodes) || !Array.isArray(subgraph.edges)) {
			issues.push(`Subgraph ${subgraph?.name || subgraph?.id || "(unnamed)"} is malformed.`)
		}
	}

	return issues
}

function repairAutomation(config: AutomationConfig): AutomationConfig {
	const repaired = cloneAutomationConfig(config)
	repaired.name ||= ""
	repaired.graph = repairGraphModel(repaired.graph)
	repaired.subgraphs = Array.isArray(repaired.subgraphs) ? repaired.subgraphs.map(repairSubgraph).filter(Boolean) as SubgraphDefinition[] : []
	const mainWireNodeIds = new Set(repaired.graph.nodes.map((node) => node.id))
	mainWireNodeIds.add("trigger")
	repaired.dataWires = repairDataWires(repaired.dataWires, mainWireNodeIds)
	repaired.variableNodes = repairVariableNodes(repaired.variableNodes)
	return repaired
}

function cloneAutomationConfig(config: AutomationConfig): AutomationConfig {
	return JSON.parse(JSON.stringify(toRaw(config))) as AutomationConfig
}

function repairGraphModel(graph: AutomationGraph | undefined): AutomationGraph {
	if (!graph || !Array.isArray(graph.nodes) || !Array.isArray(graph.edges)) return { nodes: [], edges: [], entryNodeId: "" }
	const nodes = dedupeNodes(graph.nodes)
	const nodeIds = new Set(nodes.map((node) => node.id))
	const edges = graph.edges
		.filter((edge) => edge?.id && nodeIds.has(edge.from) && nodeIds.has(edge.to))
		.map((edge) => ({ id: String(edge.id), from: edge.from, to: edge.to, port: edge.port }))
	return {
		nodes,
		edges,
		entryNodeId: graph.entryNodeId && nodeIds.has(graph.entryNodeId) ? graph.entryNodeId : nodes[0]?.id ?? "",
	}
}

function repairSubgraph(subgraph: SubgraphDefinition): SubgraphDefinition | undefined {
	if (!subgraph?.id || !Array.isArray(subgraph.nodes) || !Array.isArray(subgraph.edges)) return undefined
	const repaired = repairGraphModel(subgraph)
	const wireNodeIds = new Set(repaired.nodes.map((node) => node.id))
	for (const param of subgraph.parameters ?? []) {
		if (param?.name) wireNodeIds.add(`__param:${param.name}`)
	}
	return {
		...subgraph,
		nodes: repaired.nodes,
		edges: repaired.edges,
		dataWires: repairDataWires(subgraph.dataWires, wireNodeIds),
		entryNodeId: repaired.entryNodeId,
		parameters: Array.isArray(subgraph.parameters) ? subgraph.parameters : [],
		outputs: Array.isArray(subgraph.outputs) ? subgraph.outputs : [],
	}
}

function dedupeNodes(nodes: GraphNode[]): GraphNode[] {
	const seen = new Set<string>()
	return nodes
		.filter((node) => node?.id && !seen.has(node.id) && VALID_NODE_TYPES.has(String(node.type)))
		.map((node) => {
			seen.add(node.id)
			return {
				...node,
				x: Number.isFinite(Number(node.x)) ? Number(node.x) : 0,
				y: Number.isFinite(Number(node.y)) ? Number(node.y) : 0,
			} as GraphNode
		})
}

function repairDataWires(wires: AutomationDataWire[] | undefined, nodeIds: Set<string>): AutomationDataWire[] {
	if (!Array.isArray(wires)) return []
	return wires.filter((wire) => wire?.id && nodeIds.has(wire.fromNode) && nodeIds.has(wire.toNode) && wire.fromPort && wire.toPort)
}

function repairVariableNodes(nodes: AutomationVariableNode[] | undefined): AutomationVariableNode[] {
	if (!Array.isArray(nodes)) return []
	return nodes.filter((node) => node?.id && node?.name && VALID_VARIABLE_TYPES.has(String(node.type)))
}
</script>

<style scoped>
.automation-edit-page {
	position: relative;
	display: flex;
	height: 100%;
	--trigger-color: #3e3e3e;
	--darker-trigger-color: #2e2e2e;
	--darkest-trigger-color: #1e1e1e;
	--lighter-trigger-color: #4e4e4e;
}

.automation-edit-page__error {
	display: grid;
	align-content: start;
	gap: 0.75rem;
	width: 100%;
	margin: 1rem;
	border: 1px solid rgba(255, 120, 120, 0.45);
	border-radius: 6px;
	background: rgba(50, 10, 14, 0.82);
	color: #ffe8e8;
	padding: 1rem;
	white-space: pre-wrap;
}

.automation-edit-page__recovery {
	display: grid;
	align-content: start;
	gap: 1rem;
	width: 100%;
	margin: 1rem;
	border: 1px solid rgba(255, 183, 77, 0.45);
	border-radius: 6px;
	background: rgba(38, 28, 8, 0.9);
	color: #fff4d7;
	padding: 1rem;
}

.automation-edit-page__eyebrow {
	margin: 0 0 0.25rem;
	color: #ffcf7a;
	font-size: 0.7rem;
	font-weight: 700;
	letter-spacing: 0.08em;
	text-transform: uppercase;
}

.automation-edit-page__recovery h2,
.automation-edit-page__recovery p {
	margin: 0;
}

.automation-edit-page__recovery ul {
	margin: 0;
	padding-left: 1.2rem;
}

.automation-edit-page__actions {
	display: flex;
	flex-wrap: wrap;
	gap: 0.5rem;
}

.automation-edit-page__actions button {
	border: 1px solid rgba(255, 207, 122, 0.35);
	border-radius: 4px;
	background: rgba(255, 207, 122, 0.14);
	color: #fff4d7;
	padding: 0.45rem 0.7rem;
}

.automation-edit-page__recovery textarea {
	min-height: 18rem;
	border: 1px solid rgba(255, 207, 122, 0.25);
	border-radius: 4px;
	background: rgba(0, 0, 0, 0.35);
	color: #ffe9b4;
	font-family: ui-monospace, SFMono-Regular, Consolas, "Liberation Mono", monospace;
	font-size: 0.8rem;
	padding: 0.75rem;
	resize: vertical;
}

.automation-edit-page__error code,
.automation-edit-page__error small {
	color: #ffd0d0;
	font-size: 0.8rem;
	word-break: break-word;
}

.config {
	background-color: var(--surface-b);
	user-select: none;
	width: 350px;
	overflow-y: auto;
	overflow-x: visible;
}
</style>
