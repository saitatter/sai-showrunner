import type { UpdateStatus } from "showrunner-schema"

export interface UpdateStatusView {
	statusClass: string
	statusTitle: string
	statusDetail: string
	latestVersionLabel: string
}

export function getUpdateStatusView(status: UpdateStatus | undefined): UpdateStatusView {
	return {
		statusClass: getUpdateStatusClass(status),
		statusTitle: getUpdateStatusTitle(status),
		statusDetail: getUpdateStatusDetail(status),
		latestVersionLabel: getLatestVersionLabel(status),
	}
}

function getUpdateStatusClass(status: UpdateStatus | undefined) {
	if (status?.error) return "updates-page__status--error"
	if (status && !status.canCheckForUpdates) return "updates-page__status--muted"
	if (status?.downloaded) return "updates-page__status--available"
	if (status?.hasUpdate) return "updates-page__status--available"
	return "updates-page__status--current"
}

function getUpdateStatusTitle(status: UpdateStatus | undefined) {
	if (status?.error) return "Update check failed"
	if (status && !status.canCheckForUpdates) return "Development build"
	if (status?.downloaded) return "Update downloaded"
	if (status?.hasUpdate) return "Update available"
	if (status?.checkedAt) return "You're up to date"
	return "Ready to check"
}

function getUpdateStatusDetail(status: UpdateStatus | undefined) {
	if (!status) return "Check GitHub Releases to compare this build with the latest published update."
	if (status.error) return friendlyUpdateError(status.error)
	if (status.message) return status.message
	if (status.downloaded) return "The update is downloaded and ready to install on restart."
	if (status.hasUpdate && status.update) return `v${status.currentVersion} -> v${status.update.version}`
	if (status.checkedAt) return `ShowRunner v${status.currentVersion} is the current installed version.`
	return "Check GitHub Releases to compare this build with the latest published update."
}

function getLatestVersionLabel(status: UpdateStatus | undefined) {
	const latest = status?.latest ?? status?.update
	return latest?.version ? `v${latest.version}` : "unknown"
}

export function friendlyUpdateError(error: string) {
	if (/\b(ENOTFOUND|ECONNRESET|ECONNREFUSED|ETIMEDOUT|EAI_AGAIN|network|offline)\b/i.test(error)) {
		return "Could not reach the update server. Check your internet connection and try again."
	}
	return error
}
