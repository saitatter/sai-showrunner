import { describe, expect, it } from "vitest"
import {
	defaultCoreConversionConfig,
	defaultCoreConversionResultMapping,
	getCoreConversionActionDefinition,
} from "./coreConversionActions"

describe("coreConversionActions", () => {
	it("resolves core conversion schemas across plugin and action id formats", () => {
		const camelDefinition = getCoreConversionActionDefinition("ShowRunner", "convertJsonStringToObject")
		const kebabDefinition = getCoreConversionActionDefinition("showrunner", "convert-json-string-to-object")

		expect(camelDefinition?.name).toBe("Convert JSON String To Object")
		expect(kebabDefinition).toBe(camelDefinition)
		expect(camelDefinition?.config?.properties).toHaveProperty("value")
		expect(camelDefinition?.result?.properties).toHaveProperty("converted")
	})

	it("does not resolve fallback conversions for external plugins", () => {
		expect(getCoreConversionActionDefinition("youtube", "convertJsonStringToObject")).toBeUndefined()
	})

	it("provides default config for created conversion nodes", () => {
		expect(defaultCoreConversionConfig("convertJsonStringToObject")).toEqual({ value: "{}" })
		expect(defaultCoreConversionConfig("convert-json-string-to-array")).toEqual({ value: "[]" })
		expect(defaultCoreConversionConfig("convertStringToNumber")).toEqual({ value: "", fallback: 0 })
	})

	it("maps conversion result ports including converted flags where available", () => {
		expect(defaultCoreConversionResultMapping("convertNumberToString")).toEqual({ value: "value" })
		expect(defaultCoreConversionResultMapping("convert-json-string-to-object")).toEqual({
			value: "value",
			converted: "converted",
		})
	})
})
