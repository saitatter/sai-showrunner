/**
 * Shared helpers for overlay runtime configuration parsing.
 */

/** Safely parse a URL, returning fallback on failure */
export function safeUrl(raw: string | undefined | null, fallback = ""): string {
	if (!raw) return fallback
	try {
		const base = typeof window !== "undefined" ? window.location.origin : undefined
		return new URL(raw, base).href
	} catch {
		return fallback
	}
}

/** Read a boolean flag from URLSearchParams */
export function readFlag(params: URLSearchParams, key: string, defaultValue = false): boolean {
	const value = params.get(key)
	if (value === null) return defaultValue
	return value === "true" || value === "1" || value === ""
}

/** Read a numeric value from URLSearchParams */
export function readNumber(params: URLSearchParams, key: string, defaultValue = 0): number {
	const value = params.get(key)
	if (value === null) return defaultValue
	const parsed = Number(value)
	return Number.isFinite(parsed) ? parsed : defaultValue
}

/** Safely parse a hex color string to normalized [r, g, b] */
export function safeColor(hex: string | undefined | null, fallback: [number, number, number]): [number, number, number] {
	if (!hex) return fallback
	const match = String(hex).match(/^#?([0-9a-f]{3}|[0-9a-f]{6})$/i)
	if (!match) return fallback
	let value = match[1]
	if (value.length === 3) value = value.split("").map((c) => c + c).join("")
	const parsed = Number.parseInt(value, 16)
	return [((parsed >> 16) & 255) / 255, ((parsed >> 8) & 255) / 255, (parsed & 255) / 255]
}

/** Normalize a widget instance ID (strip leading slashes, lowercase) */
export function normalizeInstance(id: string | undefined | null): string {
	if (!id) return ""
	return id.replace(/^\/+/, "").toLowerCase()
}
