import { describe, it, expect } from "vitest"
import { hashString, getByPath, setByPath, mapMap, mapRecord, isKey } from "../type-helpers"

describe("hashString", () => {
	it("should return a number", () => {
		expect(typeof hashString("test")).toBe("number")
	})

	it("should be deterministic", () => {
		expect(hashString("hello")).toBe(hashString("hello"))
	})

	it("should produce different hashes for different strings", () => {
		expect(hashString("hello")).not.toBe(hashString("world"))
	})

	it("should accept a seed parameter", () => {
		expect(hashString("test", 1)).not.toBe(hashString("test", 2))
	})

	it("should handle empty string", () => {
		expect(typeof hashString("")).toBe("number")
	})
})

describe("getByPath", () => {
	it("should get a top-level property", () => {
		expect(getByPath({ a: 1 }, "a")).toBe(1)
	})

	it("should get a nested property", () => {
		expect(getByPath({ a: { b: { c: 42 } } }, "a.b.c")).toBe(42)
	})

	it("should return undefined for missing path", () => {
		expect(getByPath({ a: 1 }, "b")).toBeUndefined()
	})
})

describe("setByPath", () => {
	it("should set a top-level property", () => {
		const obj = { a: 1 }
		setByPath(obj, "a", 2)
		expect(obj.a).toBe(2)
	})

	it("should set a nested property", () => {
		const obj = { a: { b: { c: 1 } } }
		setByPath(obj, "a.b.c", 99)
		expect(obj.a.b.c).toBe(99)
	})
})

describe("mapMap", () => {
	it("should transform map values", () => {
		const input = new Map([
			["a", 1],
			["b", 2],
		])
		const result = mapMap(input, (k, v) => v * 10)
		expect(result.get("a")).toBe(10)
		expect(result.get("b")).toBe(20)
	})

	it("should handle empty map", () => {
		const result = mapMap(new Map(), (k, v) => v)
		expect(result.size).toBe(0)
	})
})

describe("mapRecord", () => {
	it("should transform map to record", () => {
		const input = new Map([
			["x", 3],
			["y", 4],
		])
		const result = mapRecord(input, (k, v) => v + 1)
		expect(result).toEqual({ x: 4, y: 5 })
	})
})

describe("isKey", () => {
	it("should return true for string", () => {
		expect(isKey("hello")).toBe(true)
	})

	it("should return true for number", () => {
		expect(isKey(42)).toBe(true)
	})

	it("should return true for symbol", () => {
		expect(isKey(Symbol("s"))).toBe(true)
	})

	it("should return false for objects", () => {
		expect(isKey({})).toBe(false)
		expect(isKey(null)).toBe(false)
		expect(isKey(undefined)).toBe(false)
	})
})
