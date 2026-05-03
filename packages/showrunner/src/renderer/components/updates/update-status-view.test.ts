import { describe, expect, it } from "vitest"
import type { UpdateStatus } from "showrunner-schema"
import { friendlyUpdateError, getUpdateStatusView } from "./update-status-view"

const baseStatus: UpdateStatus = {
	currentVersion: "1.0.0",
	hasUpdate: false,
	canCheckForUpdates: true,
	checking: false,
}

describe("update status view", () => {
	it("shows development build state when update checks are unavailable", () => {
		expect(
			getUpdateStatusView({
				...baseStatus,
				canCheckForUpdates: false,
				message: "Update checks run in packaged builds.",
			})
		).toMatchObject({
			statusTitle: "Development build",
			statusDetail: "Update checks run in packaged builds.",
			statusClass: "updates-page__status--muted",
		})
	})

	it("shows offline update errors without exposing low-level network noise", () => {
		expect(friendlyUpdateError("connect ETIMEDOUT github.com")).toBe(
			"Could not reach the update server. Check your internet connection and try again."
		)
	})

	it("shows no-update state after a successful check", () => {
		expect(getUpdateStatusView({ ...baseStatus, checkedAt: "2026-05-03T12:00:00.000Z" })).toMatchObject({
			statusTitle: "You're up to date",
			statusDetail: "ShowRunner v1.0.0 is the current installed version.",
			statusClass: "updates-page__status--current",
		})
	})

	it("shows update-available state", () => {
		expect(
			getUpdateStatusView({
				...baseStatus,
				hasUpdate: true,
				update: { version: "1.0.1", name: "Release", date: "", notes: "" },
			})
		).toMatchObject({
			statusTitle: "Update available",
			statusDetail: "v1.0.0 -> v1.0.1",
			latestVersionLabel: "v1.0.1",
		})
	})

	it("shows downloaded state before generic available state", () => {
		expect(
			getUpdateStatusView({
				...baseStatus,
				hasUpdate: true,
				downloaded: true,
				update: { version: "1.0.1", name: "Release", date: "", notes: "" },
			})
		).toMatchObject({
			statusTitle: "Update downloaded",
			statusDetail: "The update is downloaded and ready to install on restart.",
		})
	})
})
