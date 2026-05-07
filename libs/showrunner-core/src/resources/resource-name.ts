export function normalizeRequiredResourceName(name: unknown, label = "Resource name") {
	const normalized = String(name ?? "").trim()
	if (!normalized) {
		throw new Error(`${label} cannot be empty`)
	}
	return normalized
}
