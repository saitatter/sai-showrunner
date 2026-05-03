export interface UpdateData {
	version: string
	name: string
	date: string
	notes: string
}

export interface UpdateStatus {
	currentVersion: string
	latest?: UpdateData
	update?: UpdateData
	hasUpdate: boolean
	canCheckForUpdates: boolean
	checkedAt?: string
	error?: string
	message?: string
	checking: boolean
}
