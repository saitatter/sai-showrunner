import type { ActionDefinition } from "showrunner-ui-core"
import { normalizeActionLookupId, resolveMapById, resolveRecordById } from "showrunner-schema"

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
	if (normalizeActionLookupId(pluginId) !== "showrunner") return undefined
	return CORE_CONVERSION_ACTION_DEFINITIONS[normalizeActionLookupId(actionId)]
}

const CORE_CONVERSION_ACTION_DEFINITIONS: Record<string, ActionDefinition> = Object.fromEntries([
	coreConversionAction("convertNumberToString", "Convert Number To String", "mdi mdi-swap-horizontal", { value: { type: Number, name: "Number", required: true } }, { value: { type: String, name: "Text" } }),
	coreConversionAction("convertBooleanToString", "Convert Boolean To String", "mdi mdi-swap-horizontal", { value: { type: Boolean, name: "Boolean", required: true } }, { value: { type: String, name: "Text" } }),
	coreConversionAction("convertStringToNumber", "Convert String To Number", "mdi mdi-swap-horizontal", { value: { type: String, name: "Text", required: true }, fallback: { type: Number, name: "Fallback", default: 0 } }, { value: { type: Number, name: "Number" }, converted: { type: Boolean, name: "Converted" } }),
	coreConversionAction("convertBooleanToNumber", "Convert Boolean To Number", "mdi mdi-swap-horizontal", { value: { type: Boolean, name: "Boolean", required: true } }, { value: { type: Number, name: "Number" } }),
	coreConversionAction("convertNumberToBoolean", "Convert Number To Boolean", "mdi mdi-swap-horizontal", { value: { type: Number, name: "Number", required: true } }, { value: { type: Boolean, name: "Boolean" } }),
	coreConversionAction("convertStringToBoolean", "Convert String To Boolean", "mdi mdi-swap-horizontal", { value: { type: String, name: "Text", required: true }, fallback: { type: Boolean, name: "Fallback", default: false } }, { value: { type: Boolean, name: "Boolean" }, converted: { type: Boolean, name: "Converted" } }),
	coreConversionAction("convertObjectToJsonString", "Convert Object To JSON String", "mdi mdi-code-json", { value: { type: Object, name: "Object", required: true } }, { value: { type: String, name: "JSON" } }),
	coreConversionAction("convertArrayToJsonString", "Convert Array To JSON String", "mdi mdi-code-json", { value: { type: Array, name: "Array", required: true } }, { value: { type: String, name: "JSON" } }),
	coreConversionAction("convertJsonStringToObject", "Convert JSON String To Object", "mdi mdi-code-json", { value: { type: String, name: "JSON", required: true } }, { value: { type: Object, name: "Object" }, converted: { type: Boolean, name: "Converted" } }),
	coreConversionAction("convertJsonStringToArray", "Convert JSON String To Array", "mdi mdi-code-json", { value: { type: String, name: "JSON", required: true } }, { value: { type: Array, name: "Array" }, converted: { type: Boolean, name: "Converted" } }),
].map((definition) => [normalizeActionLookupId(definition.id), definition]))

function coreConversionAction(id: string, name: string, icon: string, configProperties: Record<string, any>, resultProperties: Record<string, any>): ActionDefinition {
	return {
		id,
		name,
		icon,
		type: "regular",
		duration: { dragType: "instant" },
		config: { type: Object, properties: configProperties },
		result: { type: Object, properties: resultProperties },
	}
}
