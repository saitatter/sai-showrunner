import { useToast } from "primevue/usetoast"

type FeedbackSeverity = "success" | "info" | "warn" | "error"

function messageFromError(error: unknown) {
	if (error instanceof Error) return error.message
	return String(error)
}

function isDevRuntime() {
	return !!(import.meta as unknown as { env?: { DEV?: boolean } }).env?.DEV
}

export function useAppFeedback(scope = "ShowRunner") {
	const toast = useToast()

	function notify(severity: FeedbackSeverity, summary: string, detail?: string, life = severity === "error" ? 5000 : 1800) {
		toast.add({ severity, summary, detail, life })
	}

	function logDev(method: "debug" | "info" | "warn" | "error", summary: string, detail?: unknown) {
		if (!isDevRuntime()) return
		const message = `[${scope}] ${summary}`
		if (detail === undefined) console[method](message)
		else console[method](message, detail)
	}

	return {
		success(summary: string, detail?: string, life?: number) {
			notify("success", summary, detail, life)
			logDev("info", summary, detail)
		},
		info(summary: string, detail?: string, life?: number) {
			notify("info", summary, detail, life)
			logDev("info", summary, detail)
		},
		warn(summary: string, detail?: string, life?: number) {
			notify("warn", summary, detail, life)
			logDev("warn", summary, detail)
		},
		error(summary: string, error?: unknown, life?: number) {
			const detail = error == null ? undefined : messageFromError(error)
			notify("error", summary, detail, life)
			logDev("error", summary, error)
		},
		debug(summary: string, detail?: unknown) {
			logDev("debug", summary, detail)
		},
	}
}
