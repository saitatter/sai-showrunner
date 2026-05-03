import { describe, expect, it } from "vitest"
import { areTypesCompatible, wouldCreateDataWireCycle, type DataWire } from "./usePortConnections"

describe("port connection validation", () => {
	it("accepts exact matches, aliases, and any ports", () => {
		expect(areTypesCompatible("string", "str")).toBe(true)
		expect(areTypesCompatible("number", "num")).toBe(true)
		expect(areTypesCompatible("any", "object")).toBe(true)
	})

	it("rejects incompatible port types", () => {
		expect(areTypesCompatible("number", "string")).toBe(false)
		expect(areTypesCompatible("boolean", "number")).toBe(false)
		expect(areTypesCompatible("bool", "str")).toBe(false)
		expect(areTypesCompatible("object", "string")).toBe(false)
		expect(areTypesCompatible("array", "number")).toBe(false)
		expect(areTypesCompatible("color", "boolean")).toBe(false)
	})

	it("detects cycles through existing data wires", () => {
		const wires: DataWire[] = [
			{ id: "a-b", fromNode: "a", fromPort: "value", toNode: "b", toPort: "value" },
			{ id: "b-c", fromNode: "b", fromPort: "value", toNode: "c", toPort: "value" },
		]

		expect(wouldCreateDataWireCycle(wires, "c", "a")).toBe(true)
		expect(wouldCreateDataWireCycle(wires, "c", "d")).toBe(false)
	})
})
