import type { ActionDefinition } from "showrunner-ui-core"
import { normalizeActionLookupId, resolveMapById, resolveRecordById } from "showrunner-schema"
import { getCoreConversionActionDefinition, isCoreConversionAction, normalizeCoreConversionActionId } from "./coreConversionActions"

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
	return resolveActionFromRecord(actions, actionId) ??
		resolveCoreConversionActionFromRecord(actions, pluginId, actionId) ??
		resolveCoreActionDefinition(pluginId, actionId)
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

function resolveCoreConversionActionFromRecord(
	actions: Record<string, ActionDefinition> | undefined,
	pluginId: string,
	actionId: string
) {
	if (!actions || normalizeActionLookupId(pluginId) !== "showrunner" || !isCoreConversionAction(pluginId, actionId)) return undefined
	const normalizedActionId = normalizeCoreConversionActionId(actionId)
	for (const key in actions) {
		if (normalizeCoreConversionActionId(key) === normalizedActionId) return actions[key]
	}
	return undefined
}

function resolveCoreActionDefinition(pluginId: string, actionId: string) {
	return getCoreConversionActionDefinition(pluginId, actionId)
}
