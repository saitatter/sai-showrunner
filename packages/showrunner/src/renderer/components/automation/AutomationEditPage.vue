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
import { AutomationConfig } from "showrunner-schema"
import { AutomationResourceView, useAppFeedback, useDocumentId, useResourceStore } from "showrunner-ui-core"
import { computed, onErrorCaptured, ref, useModel } from "vue"
import NodeAutomationEdit from "./NodeAutomationEdit.vue"
import { cloneAutomationConfig, repairAutomation, validateAutomationGraph } from "./automation-graph-recovery"

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
