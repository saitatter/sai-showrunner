export interface UnifiedChatMessage {
	id: string
	platform: string
	displayName: string
	message: string
	badges: string[]
	expiresInMs?: number
}

export function decodeUnifiedChat(value: unknown): UnifiedChatMessage[] {
	if (!value || typeof value !== "object") throw new Error("Invalid chat snapshot")
	const snapshot = value as Record<string, unknown>
	if (snapshot.version !== 1 || !Array.isArray(snapshot.messages) || snapshot.messages.length > 200) throw new Error("Unsupported chat snapshot")
	const ids = new Set<string>()
	return snapshot.messages.map((raw: unknown) => {
		if (!raw || typeof raw !== "object") throw new Error("Invalid chat entry")
		const row = raw as Record<string, unknown>
		const text = (key: string, max: number) => {
			const value = row[key]
			if (typeof value !== "string" || [...value].length > max) throw new Error("Invalid chat text")
			return value
		}
		const id = text("id", 512), platform = text("platform", 32)
		if (!id || ids.has(id) || !["twitch", "youtube", "kick"].includes(platform)) throw new Error("Invalid chat identity")
		ids.add(id)
		const badges = row.badges ?? []
		const expiry = row.expiresInMs
		if (!Array.isArray(badges) || badges.length > 8 || badges.some(b => typeof b !== "string" || [...b].length > 64) ||
			(expiry !== undefined && (typeof expiry !== "number" || !Number.isFinite(expiry) || expiry < 0 || expiry > 86_400_000))) throw new Error("Invalid chat metadata")
		return {id, platform, displayName: text("displayName", 256), message: text("message", 4096), badges: [...badges] as string[],
			...(expiry !== undefined ? {expiresInMs: expiry as number} : {})}
	})
}

/** One bounded reader per mounted unified-chat widget. Snapshot replacement
 * propagates message deletion, clears and ignore preference changes. */
export class UnifiedChatFeedSource {
	private generation = 0
	private closed = true
	private pollTimer?: ReturnType<typeof setTimeout>
	private requestTimer?: ReturnType<typeof setTimeout>
	private abort?: AbortController
	private readonly expiryTimers = new Set<ReturnType<typeof setTimeout>>()
	private messages: UnifiedChatMessage[] = []
	constructor(private readonly overlayId: string, private readonly widgetId: string,
		private readonly update: (messages: UnifiedChatMessage[]) => void,
		private readonly status: (value: "ready" | "unavailable") => void = () => {}) {}

	start(): void {
		this.stop()
		this.closed = false
		void this.poll(this.generation)
	}
	stop(): void {
		this.closed = true
		this.generation++
		if (this.pollTimer !== undefined) clearTimeout(this.pollTimer)
		this.pollTimer = undefined
		if (this.requestTimer !== undefined) clearTimeout(this.requestTimer)
		this.requestTimer = undefined
		this.abort?.abort()
		this.abort = undefined
		this.clearExpiry()
		this.messages = []
	}
	private clearExpiry(): void {
		for (const timer of this.expiryTimers) clearTimeout(timer)
		this.expiryTimers.clear()
	}
	private async poll(generation: number): Promise<void> {
		const abort = new AbortController()
		this.abort = abort
		const timeout = setTimeout(() => abort.abort(), 5000)
		this.requestTimer = timeout
		try {
			const response = await fetch(`/overlays/${encodeURIComponent(this.overlayId)}/chat/${encodeURIComponent(this.widgetId)}`,
				{credentials: "same-origin", cache: "no-store", signal: abort.signal})
			if (!response.ok) throw new Error("Chat unavailable")
			const messages = decodeUnifiedChat(await response.json())
			if (this.closed || generation !== this.generation || abort.signal.aborted) return
			this.clearExpiry()
			this.messages = messages.filter(m => m.expiresInMs !== 0)
			this.update(this.messages)
			this.status("ready")
			for (const message of this.messages) {
				if (message.expiresInMs === undefined) continue
				const timer = setTimeout(() => {
					this.expiryTimers.delete(timer)
					if (this.closed || generation !== this.generation) return
					this.messages = this.messages.filter(m => m.id !== message.id)
					this.update(this.messages)
				}, message.expiresInMs)
				this.expiryTimers.add(timer)
			}
		} catch {
			if (!this.closed && generation === this.generation) this.status("unavailable")
		} finally {
			clearTimeout(timeout)
			if (this.requestTimer === timeout) this.requestTimer = undefined
			if (this.abort === abort) this.abort = undefined
			if (!this.closed && generation === this.generation) this.pollTimer = setTimeout(() => void this.poll(generation), 1000)
		}
	}
}
