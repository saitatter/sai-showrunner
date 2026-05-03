<template>
	<base-obs-action-component :obs="model.obs">
		<obs-source-ref :obs="model.obs" :scene="model.scene" :source="model.source" />
		<i class="mdi mdi-move-resize" />
	</base-obs-action-component>
</template>

<script setup lang="ts">
import { Toggle } from "showrunner-schema"
import BaseObsActionComponent from "./BaseObsActionComponent.vue"
import ObsSourceRef from "./ObsSourceRef.vue"
import { computed } from "vue"
import { OBSSourceTransform } from "showrunner-plugin-obs-shared"

const model = defineModel<{
	obs: string
	scene: string
	source: number
	transform: OBSSourceTransform
}>({ required: true })
</script>

<style scoped></style>
