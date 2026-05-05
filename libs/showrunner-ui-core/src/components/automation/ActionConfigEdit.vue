<template>
	<div v-if="actionInfo">
		<div class="action-header">
			<h3>
				<i v-if="actionInfo.icon" :class="actionInfo.icon" :style="{ color: actionInfo.color }" />{{
					actionInfo.name
				}}
			</h3>
			<p v-if="actionInfo.description">{{ actionInfo.description }}</p>
		</div>
		<data-input v-model="model.config" :schema="actionInfo.config" :context="model.config" local-path="config" />
		<template v-if="actionInfo.type == 'regular' && actionInfo.result">
			<div class="section-title">
				<span style="text-align: center; flex: 1">Returns</span>
			</div>
			<return-namer v-model="model.resultMapping" :result-schema="actionInfo.result" />
		</template>
	</div>
</template>

<script setup lang="ts">
import { ActionInfo } from "showrunner-schema"
import { useAction, DataInput, useDataBinding, type ActionDefinition } from "../../main"
import { computed, useModel } from "vue"
import ReturnNamer from "../data/returns/ReturnNamer.vue"

const props = defineProps<{
	modelValue: ActionInfo
	localPath: string | undefined
	resolvedActionDefinition?: ActionDefinition
}>()

useDataBinding(() => props.localPath)

const model = useModel(props, "modelValue")

const registeredActionInfo = useAction(() => props.modelValue)
const actionInfo = computed(() => props.resolvedActionDefinition ?? registeredActionInfo.value)
</script>

<style scoped>
.action-header {
	padding-left: 0.5rem;
	padding-right: 0.5rem;
	padding-top: 0.5rem;
}

.action-header p {
	margin: 0;
	font-size: 0.8em;
}

.action-header h3 {
	margin: 0;
	text-align: center;
}

.action-header h3 i {
	margin-right: 0.3em;
}

.flow-header {
	display: flex;
	flex-direction: row;
	align-items: center;
}

.section-title {
	display: flex;
	flex-direction: row;
	align-items: center;
}
</style>
