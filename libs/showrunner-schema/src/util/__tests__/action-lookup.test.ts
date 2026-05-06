import { describe, expect, it } from "vitest"
import { normalizeActionLookupId, resolveMapById, resolveRecordById } from "../action-lookup"

describe("action lookup helpers", () => {
	it("normalizes action ids without collapsing separators", () => {
		expect(normalizeActionLookupId(" ConvertJsonStringToObject ")).toBe("convertjsonstringtoobject")
		expect(normalizeActionLookupId("get-user")).toBe("get-user")
		expect(normalizeActionLookupId("get_user")).toBe("get_user")
	})

	it("resolves records by exact match before case-insensitive fallback", () => {
		const record = {
			"get-user": "dash",
			get_user: "underscore",
			ConvertJsonStringToObject: "camel",
		}

		expect(resolveRecordById(record, "get_user")).toBe("underscore")
		expect(resolveRecordById(record, "convertjsonstringtoobject")).toBe("camel")
		expect(resolveRecordById(record, "get user")).toBeUndefined()
	})

	it("resolves maps by exact match before case-insensitive fallback", () => {
		const map = new Map([
			["get-user", "dash"],
			["get_user", "underscore"],
			["ShowRunner", "plugin"],
		])

		expect(resolveMapById(map, "get-user")).toBe("dash")
		expect(resolveMapById(map, "showrunner")).toBe("plugin")
		expect(resolveMapById(map, "get user")).toBeUndefined()
	})
})
