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
	checkedAt?: string
	error?: string
	checking: boolean
}
