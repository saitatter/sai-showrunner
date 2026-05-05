export function normalizeActionLookupId(id: string) {
	return id.replace(/[^a-z0-9]/gi, "").toLowerCase()
}

export function resolveRecordById<T>(record: Record<string, T> | undefined, id: string | undefined) {
	if (!record || !id) return undefined
	return record[id] ?? Object.entries(record).find(([key]) => normalizeActionLookupId(key) === normalizeActionLookupId(id))?.[1] as T | undefined
}

export function resolveMapById<T>(map: Map<string, T> | undefined, id: string | undefined) {
	if (!map || !id) return undefined
	return map.get(id) ?? [...map.entries()].find(([key]) => normalizeActionLookupId(key) === normalizeActionLookupId(id))?.[1]
}
