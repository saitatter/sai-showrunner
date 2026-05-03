import { createDelayedResolver } from "showrunner-schema"
import { ipcInvoke } from "./electron"
import { ipcRenderer } from "electron"
import { defineStore } from "pinia"
import { computed, ref, markRaw } from "vue"

export const useInitStore = defineStore("init", () => {
	const mainProcessInited = ref(false)
	const mainProcessInitialInited = ref(false)

	const mainProcessInitResolver = createDelayedResolver()
	const mainProcessInitialInitResolver = createDelayedResolver()

	const mode = ref<"ShowRunner" | "satellite">("ShowRunner")

	async function initialize(appMode: "ShowRunner" | "satellite") {
		mode.value = appMode

		const isInited = await ipcInvoke("ShowRunner_isSetupFinished")
		if (isInited) {
			mainProcessInited.value = true
			mainProcessInitResolver.resolve()
		}

		const isInitialInited = await ipcInvoke("ShowRunner_isInitialSetupFinished")
		if (isInitialInited) {
			mainProcessInitialInited.value = true
			mainProcessInitialInitResolver.resolve()
		}
		//Check for init
		ipcRenderer.on("ShowRunner_setupFinished", () => {
			mainProcessInited.value = true
			mainProcessInitResolver.resolve()
		})

		ipcRenderer.on("ShowRunner_initialSetupFinished", () => {
			mainProcessInitialInited.value = true
			mainProcessInitialInitResolver.resolve()
		})
	}

	function waitForInit() {
		return mainProcessInitResolver.promise
	}

	function waitForInitialSetup() {
		return mainProcessInitialInitResolver.promise
	}

	return {
		inited: computed(() => mainProcessInited.value),
		initialize,
		waitForInitialSetup,
		waitForInit,
		mode: computed(() => mode.value),
		isShowRunner: computed(() => mode.value == "ShowRunner"),
		isSatellite: computed(() => mode.value == "satellite"),
	}
})
