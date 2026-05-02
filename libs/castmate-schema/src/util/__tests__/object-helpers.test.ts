import { describe, it, expect } from "vitest"
import { isValidJSName } from "../object-helpers"

describe("isValidJSName", () => {
	it("should accept valid identifiers", () => {
		expect(isValidJSName("foo")).toBe(true)
		expect(isValidJSName("_bar")).toBe(true)
		expect(isValidJSName("$baz")).toBe(true)
		expect(isValidJSName("camelCase")).toBe(true)
		expect(isValidJSName("PascalCase")).toBe(true)
		expect(isValidJSName("snake_case")).toBe(true)
		expect(isValidJSName("a1")).toBe(true)
	})

	it("should reject reserved words", () => {
		expect(isValidJSName("if")).toBe(false)
		expect(isValidJSName("for")).toBe(false)
		expect(isValidJSName("class")).toBe(false)
		expect(isValidJSName("return")).toBe(false)
		expect(isValidJSName("function")).toBe(false)
		expect(isValidJSName("const")).toBe(false)
		expect(isValidJSName("let")).toBe(false)
		expect(isValidJSName("var")).toBe(false)
	})

	it("should reject names starting with a digit", () => {
		expect(isValidJSName("1abc")).toBe(false)
	})

	it("should reject empty string", () => {
		expect(isValidJSName("")).toBe(false)
	})

	it("should reject names with spaces", () => {
		expect(isValidJSName("hello world")).toBe(false)
	})

	it("should reject names with special characters", () => {
		expect(isValidJSName("a-b")).toBe(false)
		expect(isValidJSName("a.b")).toBe(false)
	})
})
