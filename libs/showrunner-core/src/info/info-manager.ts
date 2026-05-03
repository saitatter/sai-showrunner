import { loadYAML, resolveProjectPath, writeYAML } from "../io/file-system"
import { Service } from "../util/service"
import fs from "fs"
import { app } from "electron"
import { defineIPCFunc } from "../util/electron"

import { autoUpdater, UpdateInfo } from "electron-updater"
import { UpdateData, UpdateStatus } from "showrunner-schema"
import { globalLogger, usePluginLogger } from "../logging/logging"
import path from "path"

import semver from "semver"

interface StartInfo {
	lastVer: string
}

const logger = usePluginLogger("info-manager")

function formatReleaseNotes(releaseNotes: UpdateInfo["releaseNotes"]) {
	if (Array.isArray(releaseNotes)) {
		return releaseNotes
			.map((releaseNote) => {
				const title = releaseNote.version ? `<h3>${releaseNote.version}</h3>` : ""
				return `${title}${releaseNote.note ?? ""}`
			})
			.join("\n")
	}

	return releaseNotes ?? ""
}

function toUpdateData(updateInfo: UpdateInfo | undefined): UpdateData | undefined {
	if (!updateInfo) return undefined

	return {
		version: updateInfo.version,
		name: updateInfo.releaseName ?? "",
		date: updateInfo.releaseDate ?? "",
		notes: formatReleaseNotes(updateInfo.releaseNotes),
	}
}

export const InfoService = Service(
	class {
		startInfo: StartInfo | undefined
		firstTimeStartup: boolean = false

		get version() {
			return app.getVersion()
		}

		updateInfo: UpdateInfo | undefined = undefined
		latestUpdateInfo: UpdateInfo | undefined = undefined
		lastUpdateCheck: string | undefined = undefined
		lastUpdateError: string | undefined = undefined
		lastUpdateMessage: string | undefined = undefined
		updateChecking: boolean = false

		constructor() {
			autoUpdater.autoInstallOnAppQuit = false
			autoUpdater.autoDownload = false
			if (!app.isPackaged && fs.existsSync(this.devUpdateConfigPath)) {
				autoUpdater.forceDevUpdateConfig = true
			}

			defineIPCFunc("info", "isFirstTimeStartup", () => {
				return this.firstTimeStartup
			})

			defineIPCFunc("info", "getUpdateInfo", () => {
				return toUpdateData(this.updateInfo)
			})

			defineIPCFunc("info", "getUpdateStatus", () => {
				return this.getUpdateStatus()
			})

			defineIPCFunc("info", "checkForUpdates", async () => {
				await this.checkUpdate()
				return this.getUpdateStatus()
			})

			defineIPCFunc("info", "hasUpdate", () => {
				return this.updateInfo != null
			})

			defineIPCFunc("info", "updateShowRunner", async () => {
				if (!this.updateInfo) {
					await this.checkUpdate()
				}
				if (!this.updateInfo) {
					throw new Error("No ShowRunner update is available.")
				}
				await autoUpdater.downloadUpdate()
				autoUpdater.quitAndInstall()
			})
		}

		getUpdateStatus(): UpdateStatus {
			return {
				currentVersion: app.getVersion(),
				latest: toUpdateData(this.latestUpdateInfo ?? this.updateInfo),
				update: toUpdateData(this.updateInfo),
				hasUpdate: this.updateInfo != null,
				canCheckForUpdates: this.canCheckForUpdates,
				checkedAt: this.lastUpdateCheck,
				error: this.lastUpdateError,
				message: this.lastUpdateMessage,
				checking: this.updateChecking,
			}
		}

		get devUpdateConfigPath() {
			return path.join(app.getAppPath(), "dev-app-update.yml")
		}

		get canCheckForUpdates() {
			return app.isPackaged || fs.existsSync(this.devUpdateConfigPath)
		}

		private async checkStartup() {
			const startInfoPath = resolveProjectPath("start-info.yaml")

			if (fs.existsSync(startInfoPath)) {
				this.startInfo = await loadYAML(startInfoPath)
			} else {
				//FIRST STARTUP
				this.firstTimeStartup = true
			}

			await this.writeStartInfo()
		}

		private async writeStartInfo() {
			this.startInfo = {
				lastVer: app.getVersion(),
			}

			await writeYAML(this.startInfo, "start-info.yaml")
		}

		async checkUpdate() {
			if (this.updateChecking) {
				return this.updateInfo != null
			}

			if (!this.canCheckForUpdates) {
				this.lastUpdateCheck = new Date().toISOString()
				this.lastUpdateError = undefined
				this.lastUpdateMessage = "Update checks run in packaged builds. Add dev-app-update.yml to test updater metadata during development."
				this.updateInfo = undefined
				return false
			}

			this.updateChecking = true
			this.lastUpdateError = undefined
			this.lastUpdateMessage = undefined
			try {
				const result = await autoUpdater.checkForUpdates()
				this.lastUpdateCheck = new Date().toISOString()
				if (result != null) {
					this.latestUpdateInfo = result.updateInfo
					if (semver.gt(result.updateInfo.version, app.getVersion())) {
						globalLogger.log("Update!", result.updateInfo.releaseName, result.updateInfo.version)
						this.updateInfo = result.updateInfo
						return true
					}
					this.updateInfo = undefined
					return false
				} else {
					globalLogger.log("No Update :(")
				}
				this.updateInfo = undefined
				return false
			} catch (err) {
				this.lastUpdateCheck = new Date().toISOString()
				this.lastUpdateError = err instanceof Error ? err.message : String(err)
				logger.error("Error Checking Update", err)
				return false
			} finally {
				this.updateChecking = false
			}
		}

		async checkInfo() {
			await this.checkStartup()
			await this.checkUpdate()
		}
	}
)
