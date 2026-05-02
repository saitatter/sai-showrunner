import { describe, it, expect } from "vitest"
import { safeUrl, readFlag, readNumber, safeColor, normalizeInstance } from "../runtime-helpers"

describe("runtime-helpers", () => {
	describe("safeUrl", () => {
		it("returns fallback for empty input", () => {
			expect(safeUrl(undefined)).toBe("")
			expect(safeUrl(null)).toBe("")
			expect(safeUrl("")).toBe("")
		})

		it("passes through absolute URLs", () => {
			const result = safeUrl("http://localhost:8080/media/test.png")
			expect(result).toBe("http://localhost:8080/media/test.png")
		})

		it("returns fallback for completely invalid URLs without a base", () => {
			// In Node there's no window.location.origin so relative paths fail gracefully
			expect(safeUrl("://broken")).toBe("")
		})
	})

	describe("readFlag", () => {
		it("returns default for missing param", () => {
			const params = new URLSearchParams("")
			expect(readFlag(params, "debug")).toBe(false)
			expect(readFlag(params, "debug", true)).toBe(true)
		})

		it("recognizes true, 1, and empty as truthy", () => {
			expect(readFlag(new URLSearchParams("x=true"), "x")).toBe(true)
			expect(readFlag(new URLSearchParams("x=1"), "x")).toBe(true)
			expect(readFlag(new URLSearchParams("x="), "x")).toBe(true)
			expect(readFlag(new URLSearchParams("x"), "x")).toBe(true)
		})

		it("recognizes false as falsy", () => {
			expect(readFlag(new URLSearchParams("x=false"), "x")).toBe(false)
			expect(readFlag(new URLSearchParams("x=0"), "x")).toBe(false)
		})
	})

	describe("readNumber", () => {
		it("returns default for missing param", () => {
			const params = new URLSearchParams("")
			expect(readNumber(params, "port")).toBe(0)
			expect(readNumber(params, "port", 8080)).toBe(8080)
		})

		it("parses valid numbers", () => {
			expect(readNumber(new URLSearchParams("port=3000"), "port")).toBe(3000)
			expect(readNumber(new URLSearchParams("val=1.5"), "val")).toBe(1.5)
		})

		it("returns default for non-numeric values", () => {
			expect(readNumber(new URLSearchParams("port=abc"), "port", 99)).toBe(99)
			expect(readNumber(new URLSearchParams("port=NaN"), "port", 99)).toBe(99)
			expect(readNumber(new URLSearchParams("port=Infinity"), "port", 99)).toBe(99)
		})
	})

	describe("safeColor", () => {
		it("parses 6-digit hex", () => {
			expect(safeColor("#ff0000", [0, 0, 0])).toEqual([1, 0, 0])
			expect(safeColor("#00ff00", [0, 0, 0])).toEqual([0, 1, 0])
			expect(safeColor("#0000ff", [0, 0, 0])).toEqual([0, 0, 1])
		})

		it("parses 3-digit hex", () => {
			expect(safeColor("#f00", [0, 0, 0])).toEqual([1, 0, 0])
		})

		it("parses without # prefix", () => {
			expect(safeColor("ff0000", [0, 0, 0])).toEqual([1, 0, 0])
		})

		it("returns fallback for invalid input", () => {
			expect(safeColor(undefined, [0.5, 0.5, 0.5])).toEqual([0.5, 0.5, 0.5])
			expect(safeColor(null, [0.5, 0.5, 0.5])).toEqual([0.5, 0.5, 0.5])
			expect(safeColor("not-a-color", [1, 1, 1])).toEqual([1, 1, 1])
			expect(safeColor("#xyz", [1, 1, 1])).toEqual([1, 1, 1])
		})
	})

	describe("normalizeInstance", () => {
		it("returns empty for null/undefined", () => {
			expect(normalizeInstance(undefined)).toBe("")
			expect(normalizeInstance(null)).toBe("")
			expect(normalizeInstance("")).toBe("")
		})

		it("strips leading slashes and lowercases", () => {
			expect(normalizeInstance("/MyWidget")).toBe("mywidget")
			expect(normalizeInstance("///test")).toBe("test")
		})

		it("keeps already clean IDs unchanged", () => {
			expect(normalizeInstance("widget-1")).toBe("widget-1")
		})
	})
})
