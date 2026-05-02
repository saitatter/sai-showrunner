import { describe, it, expect } from "vitest"
import {
	trimTemplateJS,
	regionLength,
	parseTemplateString,
	isTemplateCode,
	getTemplateRegionString,
} from "../template-utils"

describe("trimTemplateJS", () => {
	it("should strip {{ }} delimiters", () => {
		expect(trimTemplateJS("{{ foo }}")).toBe(" foo ")
	})

	it("should return undefined if not wrapped in {{ }}", () => {
		expect(trimTemplateJS("foo")).toBeUndefined()
		expect(trimTemplateJS("{{ foo")).toBeUndefined()
		expect(trimTemplateJS("foo }}")).toBeUndefined()
	})

	it("should handle nested braces", () => {
		expect(trimTemplateJS("{{ {a: 1} }}")).toBe(" {a: 1} ")
	})
})

describe("regionLength", () => {
	it("should calculate length correctly", () => {
		expect(regionLength({ startIndex: 0, endIndex: 5, type: "string" })).toBe(5)
		expect(regionLength({ startIndex: 3, endIndex: 3, type: "template" })).toBe(0)
		expect(regionLength({ startIndex: 10, endIndex: 20, type: "template" })).toBe(10)
	})
})

describe("parseTemplateString", () => {
	it("should parse a plain string as one string region", () => {
		const result = parseTemplateString("hello world")
		expect(result.fullString).toBe("hello world")
		expect(result.regions).toHaveLength(1)
		expect(result.regions[0].type).toBe("string")
	})

	it("should parse a template-only string", () => {
		const result = parseTemplateString("{{ x + 1 }}")
		expect(result.regions).toHaveLength(1)
		expect(result.regions[0].type).toBe("template")
	})

	it("should parse mixed string and template", () => {
		const result = parseTemplateString("Hello {{ name }}, welcome!")
		expect(result.regions).toHaveLength(3)
		expect(result.regions[0].type).toBe("string")
		expect(result.regions[1].type).toBe("template")
		expect(result.regions[2].type).toBe("string")
	})

	it("should handle multiple templates", () => {
		const result = parseTemplateString("{{ a }} and {{ b }}")
		expect(result.regions).toHaveLength(3)
		expect(result.regions[0].type).toBe("template")
		expect(result.regions[1].type).toBe("string")
		expect(result.regions[2].type).toBe("template")
	})

	it("should handle empty string", () => {
		const result = parseTemplateString("")
		expect(result.regions).toHaveLength(0)
	})
})

describe("isTemplateCode", () => {
	it("should return true inside template region", () => {
		const parsed = parseTemplateString("Hello {{ name }}")
		expect(isTemplateCode(parsed, 7)).toBe(true)
	})

	it("should return false inside string region", () => {
		const parsed = parseTemplateString("Hello {{ name }}")
		expect(isTemplateCode(parsed, 0)).toBe(false)
	})
})

describe("getTemplateRegionString", () => {
	it("should extract region text", () => {
		const parsed = parseTemplateString("Hello {{ name }}")
		const templateRegion = parsed.regions.find((r) => r.type === "template")!
		expect(getTemplateRegionString(parsed, templateRegion)).toBe("{{ name }}")
	})
})
