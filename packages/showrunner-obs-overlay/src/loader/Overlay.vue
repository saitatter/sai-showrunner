<template>
	<div v-if="statusVisible" class="overlay-status" :class="`overlay-status--${bridge.connectionStatus}`">
		{{ statusText }}
	</div>
	<widget-loader v-for="widget in bridge.config.widgets" :widgetConfig="widget" />
</template>

<script setup lang="ts">
import WidgetLoader from "./WidgetLoader.vue"
import { computed, onMounted } from "vue"
import { useWebsocketBridge } from "./utils/websocket"
import { loadOverlayWidgets } from "showrunner-overlay-widget-loader"
import { provideWebMediaResolver } from "showrunner-overlay-core"
import { readFlag } from "./utils/runtime-helpers"

const bridge = useWebsocketBridge()

loadOverlayWidgets()

provideWebMediaResolver()

const params = new URLSearchParams(window.location.search)
const statusVisible = readFlag(params, "statusVisible")
const isDemoMode = readFlag(params, "demo")

const statusText = computed(() => {
	switch (bridge.connectionStatus) {
		case "idle":
			return "Idle"
		case "connecting":
			return "Connecting…"
		case "connected":
			return "Connected"
		case "reconnecting":
			return "Reconnecting…"
		default:
			return bridge.connectionStatus
	}
})

onMounted(() => {
	if (!isDemoMode) {
		bridge.initialize()
	}
})
</script>

<style>
body {
	margin: 0;
}

.overlay-status {
	background: rgba(0, 0, 0, 0.7);
	border-radius: 4px;
	color: #ccc;
	font: 500 11px/1 Inter, system-ui, sans-serif;
	padding: 4px 8px;
	pointer-events: none;
	position: fixed;
	right: 6px;
	top: 6px;
	z-index: 99999;
}

.overlay-status--connected {
	color: #4cff7c;
}

.overlay-status--reconnecting {
	color: #ffb84c;
}

.overlay-status--connecting {
	color: #aaa;
}
</style>
