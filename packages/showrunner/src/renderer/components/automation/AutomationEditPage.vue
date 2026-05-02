<template>
	<div class="automation-edit-page">
		<div v-if="renderError" class="automation-edit-page__error">
			<strong>Automation editor failed</strong>
			<code>{{ renderError }}</code>
			<small>{{ debugSummary }}</small>
		</div>
		<node-automation-edit v-else v-model="safeModel" v-model:view="safeView" />
	</div>
</template>

<script setup lang="ts">
import { AutomationConfig } from "ShowRunner-schema"
import { AutomationResourceView } from "ShowRunner-ui-core"
import { computed, onErrorCaptured, ref, useModel } from "vue"
import NodeAutomationEdit from "./NodeAutomationEdit.vue"

const props = defineProps<{
	modelValue: AutomationConfig
	view: AutomationResourceView
}>()

const view = useModel(props, "view")
const model = useModel(props, "modelValue")
const renderError = ref("")

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

onErrorCaptured((error, instance, info) => {
	renderError.value = error instanceof Error ? error.stack || error.message : String(error)
	console.error("[ShowRunner AutomationEditPage] child render failed", {
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
