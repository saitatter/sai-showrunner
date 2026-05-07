export function normalizeActionLookupId(id: string) {
	return id.trim().toLowerCase()
}

export function resolveRecordById<T>(record: Record<string, T> | undefined, id: string | undefined) {
	if (!record || !id) return undefined
	const exact = record[id]
	if (exact !== undefined) return exact

	const normalizedId = normalizeActionLookupId(id)
	for (const key in record) {
		if (normalizeActionLookupId(key) === normalizedId) return record[key]
	}

	return undefined
}

export function resolveMapById<T>(map: Map<string, T> | undefined, id: string | undefined) {
	if (!map || !id) return undefined
	const exact = map.get(id)
	if (exact !== undefined) return exact

	const normalizedId = normalizeActionLookupId(id)
	for (const [key, value] of map) {
		if (normalizeActionLookupId(key) === normalizedId) return value
	}

	return undefined
}
