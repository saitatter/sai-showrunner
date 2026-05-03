import { ProjectGroupItem, usePluginStore } from "showrunner-ui-core"
import { NATIVE_INTEGRATION_PLUGIN_IDS, useInterfacePreferencesStore } from "./interface-preferences"

export function useProjectSidebarVisibility(parentGroupId?: () => string) {
	const interfacePreferences = useInterfacePreferencesStore()
	const pluginStore = usePluginStore()

	function isPluginItem(item: ProjectGroupItem) {
		return pluginStore.pluginMap.has(item.id)
	}

	function isVisible(item: ProjectGroupItem, parentId = parentGroupId?.()) {
		if (
			parentId === "integrations" &&
			interfacePreferences.preferences.hideNativeIntegrationShortcuts &&
			NATIVE_INTEGRATION_PLUGIN_IDS.has(item.id)
		) {
			return false
		}

		if (interfacePreferences.preferences.hideDisabledIntegrations && isPluginItem(item) && !pluginStore.isPluginEnabled(item.id)) {
			return false
		}

		if ("items" in item) {
			return item.items.some((child) => isVisible(child, item.id)) || Boolean(item.create)
		}

		return true
	}

	return {
		isVisible,
	}
}
