<template>
	<div class="automation-edit-page">
		<node-automation-edit v-model="model" v-model:view="view" />
	</div>
</template>

<script setup lang="ts">
import { AutomationConfig } from "ShowRunner-schema"
import { AutomationResourceView } from "ShowRunner-ui-core"
import { useModel } from "vue"
import NodeAutomationEdit from "./NodeAutomationEdit.vue"

const props = defineProps<{
	modelValue: AutomationConfig
	view: AutomationResourceView
}>()

const view = useModel(props, "view")
const model = useModel(props, "modelValue")
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
