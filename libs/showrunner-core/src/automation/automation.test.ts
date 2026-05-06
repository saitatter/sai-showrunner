import { describe, expect, it, vi } from "vitest"
import { createInlineAutomation } from "showrunner-schema"
import { Automation } from "./automation"

vi.mock("electron", () => ({
	ipcMain: { handle: vi.fn(), on: vi.fn() },
	shell: { openPath: vi.fn() },
}))

describe("Automation", () => {
	it("keeps a valid existing name when setConfig receives a malformed empty name", async () => {
		const automation = new Automation("Existing")
		vi.spyOn(automation, "save").mockResolvedValue(undefined)

		await automation.setConfig({ ...createInlineAutomation(), name: "   " })

		expect(automation.config.name).toBe("Existing")
	})
})
