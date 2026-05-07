import { describe, expect, it, vi } from "vitest"
import { Profile } from "./profile"

vi.mock("electron", () => ({
	ipcMain: { handle: vi.fn(), on: vi.fn() },
	shell: { openPath: vi.fn() },
}))

vi.mock("../plugins/plugin-manager", () => ({
	PluginManager: {
		getInstance: () => ({ state: {} }),
	},
}))

describe("Profile", () => {
	it("keeps the constructor name in config", () => {
		const profile = new Profile("Main")

		expect(profile.config.name).toBe("Main")
	})

	it("keeps a valid existing name when setConfig receives a malformed empty name", async () => {
		const profile = new Profile("Main")
		vi.spyOn(profile, "save").mockResolvedValue(undefined)

		await profile.setConfig({ ...profile.config, name: "   " })

		expect(profile.config.name).toBe("Main")
	})

	it("keeps a valid existing name when applyConfig receives a malformed empty name", async () => {
		const profile = new Profile("Main")
		vi.spyOn(profile, "save").mockResolvedValue(undefined)

		await profile.applyConfig({ name: "   " })

		expect(profile.config.name).toBe("Main")
	})
})
