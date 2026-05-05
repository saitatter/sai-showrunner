import type { ActionDefinition } from "showrunner-ui-core"

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
	return resolveActionFromRecord(actions, actionId)
}

export function resolveActionFromRecord(
	actions: Record<string, ActionDefinition> | undefined,
	actionId: string | undefined
) {
	if (!actions || !actionId) return undefined
	return actions[actionId] ?? Object.entries(actions).find(([id]) => normalizeActionLookupId(id) === normalizeActionLookupId(actionId))?.[1]
}

export function normalizeActionLookupId(actionId: string) {
	return actionId.replace(/[^a-z0-9]/gi, "").toLowerCase()
}

function resolvePlugin(pluginMap: Map<string, ActionPluginDefinition>, pluginId: string) {
	return pluginMap.get(pluginId) ?? [...pluginMap.entries()].find(([id]) => normalizeActionLookupId(id) === normalizeActionLookupId(pluginId))?.[1]
}
