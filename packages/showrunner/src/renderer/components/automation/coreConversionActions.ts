import type { ActionDefinition } from "showrunner-ui-core"
import { normalizeActionLookupId, type Schema } from "showrunner-schema"

export const CORE_CONVERSION_ACTIONS = [
	{ id: "convertNumberToString", name: "Convert Number To String", icon: "mdi mdi-swap-horizontal" },
	{ id: "convertBooleanToString", name: "Convert Boolean To String", icon: "mdi mdi-swap-horizontal" },
	{ id: "convertStringToNumber", name: "Convert String To Number", icon: "mdi mdi-swap-horizontal" },
	{ id: "convertBooleanToNumber", name: "Convert Boolean To Number", icon: "mdi mdi-swap-horizontal" },
	{ id: "convertNumberToBoolean", name: "Convert Number To Boolean", icon: "mdi mdi-swap-horizontal" },
	{ id: "convertStringToBoolean", name: "Convert String To Boolean", icon: "mdi mdi-swap-horizontal" },
	{ id: "convertObjectToJsonString", name: "Convert Object To JSON String", icon: "mdi mdi-code-json" },
	{ id: "convertArrayToJsonString", name: "Convert Array To JSON String", icon: "mdi mdi-code-json" },
	{ id: "convertJsonStringToObject", name: "Convert JSON String To Object", icon: "mdi mdi-code-json" },
	{ id: "convertJsonStringToArray", name: "Convert JSON String To Array", icon: "mdi mdi-code-json" },
]

export const CORE_CONVERSION_ACTION_DEFINITIONS: Record<string, ActionDefinition> = Object.fromEntries([
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

export function getCoreConversionActionDefinition(pluginId: string, actionId: string) {
	if (normalizeActionLookupId(pluginId) !== "showrunner") return undefined
	return CORE_CONVERSION_ACTION_DEFINITIONS[normalizeActionLookupId(actionId)]
}

export function isCoreConversionAction(pluginId: string | undefined, actionId: string | undefined) {
	if (!pluginId || !actionId) return false
	return normalizeActionLookupId(pluginId) === "showrunner" && normalizeActionLookupId(actionId) in CORE_CONVERSION_ACTION_DEFINITIONS
}

export function defaultCoreConversionConfig(actionId: string) {
	switch (normalizeActionLookupId(actionId)) {
		case "convertnumbertostring":
		case "convertnumbertoboolean":
			return { value: 0 }
		case "convertbooleantostring":
		case "convertbooleantonumber":
			return { value: false }
		case "convertstringtonumber":
			return { value: "", fallback: 0 }
		case "convertstringtoboolean":
			return { value: "", fallback: false }
		case "convertobjecttojsonstring":
			return { value: {} }
		case "convertarraytojsonstring":
			return { value: [] }
		case "convertjsonstringtoobject":
			return { value: "{}" }
		case "convertjsonstringtoarray":
			return { value: "[]" }
		default:
			return {}
	}
}

export function defaultCoreConversionResultMapping(actionId: string) {
	const resultMapping: Record<string, string> = { value: "value" }
	if (["convertstringtonumber", "convertstringtoboolean", "convertjsonstringtoobject", "convertjsonstringtoarray"].includes(normalizeActionLookupId(actionId))) {
		resultMapping.converted = "converted"
	}
	return resultMapping
}

function coreConversionAction(id: string, name: string, icon: string, configProperties: Record<string, Schema>, resultProperties: Record<string, Schema>): ActionDefinition {
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
