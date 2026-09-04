<template>
	<div class="app" @keydown="onKeyDown" tabindex="-1">
		<toast position="bottom-left" style="width: 17rem" />
		<div class="app-row" v-if="initStore.inited">
			<docking-area style="flex: 1" v-model="dockingStore.rootDockArea" />
		</div>
		<div class="load-row" v-else>
			<p-input-text v-show="false" />
			<!--We need p-input-text to be mounted to get their styles loaded-->
			<h3>Loading ShowRunner</h3>
			<p-progress-spinner />
		</div>
		<!-- <p-dynamic-dialog /> -->
		<cancellable-dynamic-dialog />
		<p-confirm-dialog />
	</div>
</template>

<script setup lang="ts">
import {
	useDockingStore,
	DockingArea,
	CancellableDynamicDialog,
	useSaveActiveTab,
	useSaveAllTabs,
	useUndoActiveTab,
	useAppFeedback,
} from "showrunner-ui-core"

import PProgressSpinner from "primevue/progressspinner"

import PConfirmDialog from "primevue/confirmdialog"

import { useInitStore } from "showrunner-ui-core"
import { onMounted } from "vue"
import PInputText from "primevue/inputtext"

import Toast from "primevue/toast"

const initStore = useInitStore()
const dockingStore = useDockingStore()

onMounted(() => {
	const queryString = window.location.search
	const urlParams = new URLSearchParams(queryString)

	const isPortable = urlParams.get("portable") == "true"
	const isDev = urlParams.get("dev") == "true"

	if (isDev) {
		document.title = "ShowRunner - Dev"
	} else if (isPortable) {
		document.title = "ShowRunner - Portable"
	}

})

const saveActiveTab = useSaveActiveTab()
const saveAllTabs = useSaveAllTabs()

const undoActiveTab = useUndoActiveTab()
const feedback = useAppFeedback("App")

function onKeyDown(ev: KeyboardEvent) {
	if (ev.ctrlKey && ev.code == "KeyS") {
		if (ev.shiftKey) {
			saveAllTabs()
		} else {
			saveActiveTab()
		}
		return ev.preventDefault()
	}

	if (ev.ctrlKey && ev.code == "KeyZ") {
		ev.preventDefault()
		undoActiveTab()
		feedback.debug("Undo active tab")
	}
}
</script>

<style>
body {
	background: #0f0f0f;
	color: white;
	margin: 0;
	font-family: var(--font-family);
	overflow: hidden;
}
</style>

<style scoped>
.app {
	width: 100vw;
	height: 100vh;
	position: relative;
	display: flex;
	flex-direction: column;
}

.app-row {
	flex: 1;
	display: flex;
	flex-direction: row;
}

.load-row {
	flex: 1;
	display: flex;
	flex-direction: column;
	align-items: center;
	justify-content: center;
}
</style>
