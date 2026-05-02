export type AppMode = "ShowRunner" | "satellite"

let mode: AppMode = "ShowRunner"

export function setAppMode(appMode: AppMode) {
	mode = appMode
}

export function getAppMode() {
	return mode
}

export function isShowRunner() {
	return mode == "ShowRunner"
}

export function isSatellite() {
	return mode == "satellite"
}
