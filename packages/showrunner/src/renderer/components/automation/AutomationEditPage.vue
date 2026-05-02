<template>
	<div class="automation-edit-page">
		<node-automation-edit v-model="safeModel" v-model:view="safeView" />
	</div>
</template>

<script setup lang="ts">
import { AutomationConfig } from "ShowRunner-schema"
import { AutomationResourceView } from "ShowRunner-ui-core"
import { computed, useModel } from "vue"
import NodeAutomationEdit from "./NodeAutomationEdit.vue"

const props = defineProps<{
	modelValue: AutomationConfig
	view: AutomationResourceView
}>()

const view = useModel(props, "view")
const model = useModel(props, "modelValue")

const safeModel = computed({
	get() {
		model.value.sequence ??= { actions: [] }
		model.value.floatingSequences ??= []
		return model.value
	},
	set(value: AutomationConfig) {
		model.value = value
	},
})

const safeView = computed({
	get() {
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
.config {
	background-color: var(--surface-b);
	user-select: none;
	width: 350px;
	overflow-y: auto;
	overflow-x: visible;
}
</style>
