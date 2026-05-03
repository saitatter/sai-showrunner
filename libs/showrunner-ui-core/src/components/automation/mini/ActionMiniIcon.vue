<template>
	<div :style="{ ...actionColorStyle }" class="mini-icon" @mouseenter="onEnter" @mouseleave="onLeave">
		<i :class="action?.icon ?? 'mdi mdi-star'" />
	</div>
	<p-popover
		v-if="highlightAction && action && Object.keys(highlightAction.config).length > 0"
		ref="popover"
		:pt="{
			root: {
				style: {
					'--p-popover-background': actionColorStyle['--action-color'],
					'--p-popover-border-color': actionColorStyle['--darker-action-color'],
				},
			},
		}"
	>
		<div class="flex flex-column align-items-center justify-content-center mini-tooltip text-center">
			<data-view :model-value="highlightAction.config" :schema="action.config" no-label />
		</div>
	</p-popover>
</template>

<script setup lang="ts">
import { ActionInfo } from "showrunner-schema"
import { ActionSelection, useAction, useActionColors, DataView } from "../../../main"
import { computed, ref } from "vue"
import PPopover from "primevue/popover"

const props = defineProps<{
	id: string
	action: ActionInfo | undefined
}>()

const highlightAction = computed(() => {
	return props.action
})

const action = useAction(highlightAction)
const { actionColorStyle } = useActionColors(highlightAction, false)

const popover = ref<InstanceType<typeof PPopover>>()

function onEnter(ev: MouseEvent) {
	popover.value?.show(ev)
}

function onLeave(ev: MouseEvent) {
	popover.value?.hide()
}
</script>

<style scoped>
.mini-tooltip {
	font-size: 0.7rem;
	max-width: 10rem;
}

.mini-icon {
	border-radius: var(--border-radius);
	height: 1.5em;
	width: 1.5em;
	display: flex;
	align-items: center;
	justify-content: center;
	background-color: var(--action-color);
}
</style>
