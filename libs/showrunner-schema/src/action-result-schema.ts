import { isObjectSchema, type Schema } from "./schema"

export function validateActionResultSchema(actionId: string, result?: Schema) {
	if (!result) return
	if (!isObjectSchema(result)) {
		throw new Error(`Action ${actionId} result schema must be an object schema with properties`)
	}
}
