<template>
	<component
		v-if="widgetComponent && widgetConfig.visible"
		:is="widgetComponent"
		:size="widgetConfig.size"
		:position="widgetConfig.position"
		:config="resolvedConfig"
		class="widget"
		:style="widgetStyle"
		ref="widget"
	>
	</component>
</template>

<script setup lang="ts">
import { OverlayWidgetConfig } from "showrunner-plugin-overlays-shared"
import { CSSProperties, computed, provide } from "vue"
import { useWebsocketBridge } from "./utils/websocket"
import { useOverlayWidgets } from "showrunner-overlay-widget-loader"
import { OverlayWidgetComponent, useResolvedWidgetConfig } from "showrunner-overlay-core"

const props = defineProps<{
	widgetConfig: OverlayWidgetConfig
}>()

const widgetStyle = computed<CSSProperties>(() => {
	return {
		left: `${props.widgetConfig.position.x}px`,
		top: `${props.widgetConfig.position.y}px`,
		width: `${props.widgetConfig.size.width}px`,
		height: `${props.widgetConfig.size.height}px`,
	}
})

const widgetStore = useOverlayWidgets()

const widgetComponent = computed<OverlayWidgetComponent | undefined>(
	() => widgetStore.getWidget(props.widgetConfig.plugin, props.widgetConfig.widget)?.component
)
// @ts-expect-error Widget component metadata type is broader than useResolvedWidgetConfig accepts here.
const resolvedConfig = useResolvedWidgetConfig(() => props.widgetConfig.config, widgetComponent)

const bridge = useWebsocketBridge()
provide("ShowRunner-bridge", bridge.getBridge(props.widgetConfig.id))
</script>

<style scoped>
.widget {
	position: absolute;
}
</style>
