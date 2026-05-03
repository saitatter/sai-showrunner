import { defineStore } from "pinia"
import { computed, ref, watch } from "vue"

export const NATIVE_INTEGRATION_PLUGIN_IDS = new Set(["moderation", "obs", "twitch", "youtube"])

export interface InterfacePreferences {
	compactProjectSidebar: boolean
	hideDisabledIntegrations: boolean
	hideNativeIntegrationShortcuts: boolean
	collapseIntegrationCategoriesByDefault: boolean
	showPluginSwitches: boolean
}

const STORAGE_KEY = "showrunner.interfacePreferences.v1"

const DEFAULT_INTERFACE_PREFERENCES: InterfacePreferences = {
	compactProjectSidebar: false,
	hideDisabledIntegrations: false,
	hideNativeIntegrationShortcuts: true,
	collapseIntegrationCategoriesByDefault: false,
	showPluginSwitches: true,
}

function loadPreferences(): InterfacePreferences {
	try {
		const stored = localStorage.getItem(STORAGE_KEY)
		if (!stored) return { ...DEFAULT_INTERFACE_PREFERENCES }

		return {
			...DEFAULT_INTERFACE_PREFERENCES,
			...(JSON.parse(stored) as Partial<InterfacePreferences>),
		}
	} catch {
		return { ...DEFAULT_INTERFACE_PREFERENCES }
	}
}

export const useInterfacePreferencesStore = defineStore("interface-preferences", () => {
	const preferences = ref(loadPreferences())

	const preferenceList = computed(() => [
		{
			key: "compactProjectSidebar" as const,
			title: "Compact project sidebar",
			description: "Use denser sidebar rows and a narrower project column.",
		},
		{
			key: "hideDisabledIntegrations" as const,
			title: "Hide disabled integrations",
			description: "Remove disabled plugin entries from the project sidebar.",
		},
		{
			key: "hideNativeIntegrationShortcuts" as const,
			title: "Hide duplicate native shortcuts",
			description: "Show Twitch, YouTube, OBS, and Moderation only inside integration categories.",
		},
		{
			key: "collapseIntegrationCategoriesByDefault" as const,
			title: "Collapse integration categories by default",
			description: "Start integration category groups collapsed when the app opens.",
		},
		{
			key: "showPluginSwitches" as const,
			title: "Show plugin switches in sidebar",
			description: "Display on/off switches next to plugin entries in the project sidebar.",
		},
	])

	function setPreference(key: keyof InterfacePreferences, value: boolean) {
		preferences.value = {
			...preferences.value,
			[key]: value,
		}
	}

	function resetPreferences() {
		preferences.value = { ...DEFAULT_INTERFACE_PREFERENCES }
	}

	watch(
		preferences,
		(value) => {
			localStorage.setItem(STORAGE_KEY, JSON.stringify(value))
		},
		{ deep: true }
	)

	return {
		preferences,
		preferenceList,
		setPreference,
		resetPreferences,
	}
})
