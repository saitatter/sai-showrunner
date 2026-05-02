import { ref } from "vue"

export interface NodeActivityEntry {
	id: number
	title: string
	detail: string
}

export function useNodeActivity(limit = 8) {
	const activityLog = ref<NodeActivityEntry[]>([])

	function logActivity(title: string, detail: string) {
		activityLog.value.unshift({ id: Date.now() + Math.random(), title, detail })
		activityLog.value = activityLog.value.slice(0, limit)
	}

	return {
		activityLog,
		logActivity,
	}
}
