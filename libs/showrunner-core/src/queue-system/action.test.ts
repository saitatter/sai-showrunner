import { describe, expect, it } from "vitest"
import { validateActionResultSchema } from "showrunner-schema"

describe("validateActionResultSchema", () => {
	it("accepts omitted and object result schemas", () => {
		expect(() => validateActionResultSchema("noop")).not.toThrow()
		expect(() =>
			validateActionResultSchema("withResult", {
				type: Object,
				properties: {
					value: { type: String },
				},
			})
		).not.toThrow()
	})

	it("rejects result schemas that cannot become graph output ports", () => {
		expect(() => validateActionResultSchema("badString", { type: String })).toThrow(
			"Action badString result schema must be an object schema with properties"
		)
		expect(() => validateActionResultSchema("badObject", { type: Object } as any)).toThrow(
			"Action badObject result schema must be an object schema with properties"
		)
		expect(() => validateActionResultSchema("badProperties", { type: Object, properties: null } as any)).toThrow(
			"Action badProperties result schema must be an object schema with properties"
		)
	})
})
