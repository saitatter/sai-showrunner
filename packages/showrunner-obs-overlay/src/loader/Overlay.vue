<template>
	<widget-loader v-for="widget in bridge.config.widgets" :widgetConfig="widget" />
</template>

<script setup lang="ts">
import WidgetLoader from "./WidgetLoader.vue"
import { computed, onMounted } from "vue"
import { useWebsocketBridge } from "./utils/websocket"
import { loadOverlayWidgets } from "ShowRunner-overlay-widget-loader"
import { provideWebMediaResolver } from "ShowRunner-overlay-core"

const bridge = useWebsocketBridge()

loadOverlayWidgets()

provideWebMediaResolver()

onMounted(() => {
	bridge.initialize()
})
</script>

<style>
body {
	margin: 0;
}
</style>
