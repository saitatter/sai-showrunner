import { describe, expect, it } from "vitest"
import { normalizeRequiredResourceName } from "./resource-name"

describe("resource name validation", () => {
	it("normalizes non-empty names", () => {
		expect(normalizeRequiredResourceName("  Main  ")).toBe("Main")
	})

	it("rejects blank names", () => {
		expect(() => normalizeRequiredResourceName("   ", "Profile name")).toThrow("Profile name cannot be empty")
	})
})
