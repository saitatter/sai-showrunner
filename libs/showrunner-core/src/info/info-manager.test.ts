import { describe, expect, it, vi } from "vitest"
import { InfoService } from "./info-manager"

const mocks = vi.hoisted(() => ({
	checkForUpdates: vi.fn(),
}))

vi.mock("electron", () => ({
	app: {
		getVersion: () => "1.0.0",
		getAppPath: () => process.cwd(),
		isPackaged: true,
	},
	ipcMain: { handle: vi.fn(), on: vi.fn() },
	shell: { openPath: vi.fn() },
}))

vi.mock("electron-updater", () => ({
	autoUpdater: {
		autoInstallOnAppQuit: false,
		autoDownload: false,
		forceDevUpdateConfig: false,
		on: vi.fn(),
		checkForUpdates: mocks.checkForUpdates,
		downloadUpdate: vi.fn(),
		quitAndInstall: vi.fn(),
	},
}))

describe("InfoService", () => {
	it("shares an in-flight update check across concurrent callers", async () => {
		const service = InfoService.initialize()
		let resolveCheck!: (value: any) => void
		mocks.checkForUpdates.mockReturnValueOnce(new Promise((resolve) => {
			resolveCheck = resolve
		}))

		const first = service.checkUpdate()
		const second = service.checkUpdate()
		let secondSettled = false
		second.then(() => {
			secondSettled = true
		})
		await Promise.resolve()

		expect(mocks.checkForUpdates).toHaveBeenCalledTimes(1)
		expect(secondSettled).toBe(false)

		resolveCheck({ updateInfo: { version: "2.0.0", releaseName: "Two" } })

		await expect(first).resolves.toBe(true)
		await expect(second).resolves.toBe(true)
		expect(service.getUpdateStatus().hasUpdate).toBe(true)
	})
})
