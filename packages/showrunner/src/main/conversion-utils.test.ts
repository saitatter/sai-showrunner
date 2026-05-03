import { describe, expect, it } from "vitest"
import {
	convertJsonStringToArray,
	convertJsonStringToObject,
	convertStringToBoolean,
	convertStringToNumber,
	parseBooleanText,
	safeJsonStringify,
} from "./conversion-utils"

describe("conversion utils", () => {
	it("parses safe boolean text variants", () => {
		expect(parseBooleanText("true")).toBe(true)
		expect(parseBooleanText(" YES ")).toBe(true)
		expect(parseBooleanText("off")).toBe(false)
		expect(parseBooleanText("0")).toBe(false)
		expect(parseBooleanText("maybe")).toBeUndefined()
	})

	it("converts string to number with fallback on invalid input", () => {
		expect(convertStringToNumber("42.5", 0)).toEqual({ value: 42.5, converted: true })
		expect(convertStringToNumber("nope", 7)).toEqual({ value: 7, converted: false })
		expect(convertStringToNumber("", 3)).toEqual({ value: 3, converted: false })
		expect(convertStringToNumber("   ", 4)).toEqual({ value: 4, converted: false })
	})

	it("converts string to boolean with fallback on unknown text", () => {
		expect(convertStringToBoolean("on", false)).toEqual({ value: true, converted: true })
		expect(convertStringToBoolean("no", true)).toEqual({ value: false, converted: true })
		expect(convertStringToBoolean("unknown", true)).toEqual({ value: true, converted: false })
	})

	it("serializes JSON safely", () => {
		expect(safeJsonStringify({ a: 1 })).toBe('{"a":1}')

		const cyclic: Record<string, unknown> = {}
		cyclic.self = cyclic
		expect(safeJsonStringify(cyclic)).toBe("")
	})

	it("parses JSON objects and arrays with converted flags", () => {
		expect(convertJsonStringToObject('{"a":1}')).toEqual({ value: { a: 1 }, converted: true })
		expect(convertJsonStringToObject("[1,2]")).toEqual({ value: {}, converted: false })
		expect(convertJsonStringToObject("{")).toEqual({ value: {}, converted: false })

		expect(convertJsonStringToArray("[1,2]")).toEqual({ value: [1, 2], converted: true })
		expect(convertJsonStringToArray('{"a":1}')).toEqual({ value: [], converted: false })
		expect(convertJsonStringToArray("{")).toEqual({ value: [], converted: false })
	})
})
