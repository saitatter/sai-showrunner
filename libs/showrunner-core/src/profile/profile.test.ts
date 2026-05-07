import { describe, expect, it, vi } from "vitest"
import { Profile } from "./profile"

vi.mock("electron", () => ({
	ipcMain: { handle: vi.fn(), on: vi.fn() },
	shell: { openPath: vi.fn() },
}))

describe("Profile", () => {
	it("keeps the constructor name in config", () => {
		const profile = new Profile("Main")

		expect(profile.config.name).toBe("Main")
	})
})
