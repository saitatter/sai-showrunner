import type { ActionDefinition } from "showrunner-ui-core"
import { resolveMapById, resolveRecordById } from "showrunner-schema"
import { getCoreConversionActionDefinition } from "./coreConversionActions"

export interface ActionPluginDefinition {
	actions?: Record<string, ActionDefinition>
}

export function resolveActionDefinition(
	pluginMap: Map<string, ActionPluginDefinition>,
	pluginId: string | undefined,
	actionId: string | undefined
) {
	if (!pluginId || !actionId) return undefined
	const actions = resolvePlugin(pluginMap, pluginId)?.actions
	return resolveActionFromRecord(actions, actionId) ?? resolveCoreActionDefinition(pluginId, actionId)
}

export function resolveActionFromRecord(
	actions: Record<string, ActionDefinition> | undefined,
	actionId: string | undefined
) {
	return resolveRecordById(actions, actionId)
}

function resolvePlugin(pluginMap: Map<string, ActionPluginDefinition>, pluginId: string) {
	return resolveMapById(pluginMap, pluginId)
}

function resolveCoreActionDefinition(pluginId: string, actionId: string) {
	return getCoreConversionActionDefinition(pluginId, actionId)
}
