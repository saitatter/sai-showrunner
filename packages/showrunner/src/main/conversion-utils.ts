export function parseBooleanText(value: unknown): boolean | undefined {
	const normalized = String(value ?? "").trim().toLowerCase()
	if (["true", "1", "yes", "y", "on"].includes(normalized)) return true
	if (["false", "0", "no", "n", "off"].includes(normalized)) return false
	return undefined
}

export function convertStringToNumber(value: unknown, fallback: unknown = 0) {
	const text = String(value ?? "").trim()
	if (text === "") {
		return {
			value: Number(fallback ?? 0),
			converted: false,
		}
	}
	const parsed = Number(text)
	const converted = Number.isFinite(parsed)
	return {
		value: converted ? parsed : Number(fallback ?? 0),
		converted,
	}
}

export function convertStringToBoolean(value: unknown, fallback: unknown = false) {
	const parsed = parseBooleanText(value)
	return {
		value: parsed ?? Boolean(fallback),
		converted: parsed !== undefined,
	}
}

export function safeJsonStringify(value: unknown): string {
	try {
		return JSON.stringify(value) ?? "null"
	} catch {
		return "null"
	}
}

export function safeJsonParse(value: unknown): unknown {
	try {
		return JSON.parse(String(value ?? ""))
	} catch {
		return undefined
	}
}

export function convertJsonStringToObject(value: unknown) {
	const parsed = safeJsonParse(value)
	const converted = parsed != null && typeof parsed === "object" && !Array.isArray(parsed)
	return { value: converted ? parsed : {}, converted }
}

export function convertJsonStringToArray(value: unknown) {
	const parsed = safeJsonParse(value)
	const converted = Array.isArray(parsed)
	return { value: converted ? parsed : [], converted }
}
