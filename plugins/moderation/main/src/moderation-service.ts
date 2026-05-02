import { ensureDirectory, ensureYAML, loadYAML, resolveProjectPath, usePluginLogger, writeYAML } from "ShowRunner-core"
import {
	ModerationActionInput,
	ModerationActionResult,
	ModerationChatEvent,
	ModerationDecisionSummary,
	ModerationOverrideRequest,
	ModerationQueueState,
	ModerationSettings,
	ModerationStatus,
} from "ShowRunner-plugin-moderation-shared"
import WebSocket from "ws"

const DEFAULT_SETTINGS: ModerationSettings = {
	enabled: false,
	apiBaseUrl: "http://localhost:8787",
	apiToken: "",
	dashboardWsUrl: "ws://localhost:8787/ws?channel=dashboard",
	forwardYouTube: true,
}

export class ModerationService {
	private static instance: ModerationService | undefined
	private logger = usePluginLogger("moderation")
	private settings: ModerationSettings = { ...DEFAULT_SETTINGS }
	private socket: WebSocket | undefined
	private reconnectTimer: NodeJS.Timeout | undefined
	private status: Omit<ModerationStatus, keyof ModerationSettings> = {
		connected: false,
		health: "unknown",
		statusMessage: "Moderation docker is not connected.",
		processedMessages: 0,
		approvedMessages: 0,
		blockedMessages: 0,
		flaggedMessages: 0,
	}
	private recentDecisions: ModerationDecisionSummary[] = []

	static getInstance() {
		this.instance ??= new ModerationService()
		return this.instance
	}

	async initialize() {
		await ensureDirectory(resolveProjectPath("moderation"))
		await ensureYAML(DEFAULT_SETTINGS, "moderation", "settings.yaml")
		this.settings = this.normalizeSettings(await loadYAML<Partial<ModerationSettings>>("moderation", "settings.yaml"))
		await this.checkHealth()
		this.connectDashboardSocket()
	}

	getStatus(): ModerationStatus {
		return { ...this.settings, ...this.status, connected: this.isSocketConnected(), recentDecisions: this.recentDecisions }
	}

	async saveSettings(settings: Partial<ModerationSettings>) {
		this.settings = this.normalizeSettings({ ...this.settings, ...settings })
		await writeYAML(this.settings, "moderation", "settings.yaml")
		await this.checkHealth()
		this.connectDashboardSocket()
		return this.getStatus()
	}

	async checkHealth() {
		if (!this.settings.enabled) {
			this.status.health = "unknown"
			this.status.statusMessage = "Moderation docker forwarding is disabled."
			return this.getStatus()
		}

		try {
			const response = await fetch(this.joinUrl(this.settings.apiBaseUrl, "/healthz"), {
				headers: this.authHeaders(),
			})
			if (!response.ok) throw new Error(`Health check failed with HTTP ${response.status}`)
			this.status.health = "healthy"
			this.status.statusMessage = "Moderation docker is reachable."
		} catch (error) {
			this.status.health = "error"
			this.status.statusMessage = error instanceof Error ? error.message : String(error)
			this.logger.error("Moderation docker health check failed.", error)
		}

		return this.getStatus()
	}

	async reconnect() {
		this.connectDashboardSocket()
		return this.getStatus()
	}

	async forwardChatMessage(event: ModerationChatEvent) {
		if (!this.settings.enabled) return
		if (event.platform === "youtube" && !this.settings.forwardYouTube) return

		try {
			const response = await fetch(this.joinUrl(this.settings.apiBaseUrl, "/v1/chat-events"), {
				method: "POST",
				headers: this.jsonHeaders(),
				body: JSON.stringify({
					id: event.id,
					messageId: event.id,
					type: "chat.message",
					source: event.source,
					platform: event.platform,
					actor: event.actor,
					payload: event.payload,
					message: event.payload.message,
					receivedAt: event.receivedAt,
				}),
			})

			if (!response.ok) throw new Error(`Moderation docker rejected event with HTTP ${response.status}`)

			this.status.processedMessages += 1
			this.status.lastEventAt = new Date().toISOString()
			this.status.statusMessage = `Forwarded ${event.platform} message to moderation docker.`
		} catch (error) {
			this.status.health = "error"
			this.status.statusMessage = error instanceof Error ? error.message : String(error)
			this.logger.error("Failed to forward chat message to moderation docker.", error)
		}
	}

	async moderateChatMessage(input: ModerationActionInput): Promise<ModerationActionResult> {
		const messageId = String(input.messageId || `showrunner-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`)
		const platform = String(input.platform || "unknown").toLowerCase()
		const viewerName = String(input.viewerName || "unknown")
		const message = String(input.message || "")
		const badges = this.parseBadges(input.badges)

		if (!this.settings.enabled) {
			return this.toActionResult({
				messageId,
				verdict: "disabled",
				confidence: 0,
				category: "disabled",
				reason: "Moderation docker integration is disabled.",
			})
		}

		try {
			const response = await fetch(this.joinUrl(this.settings.apiBaseUrl, "/v1/chat-events"), {
				method: "POST",
				headers: this.jsonHeaders(),
				body: JSON.stringify({
					id: messageId,
					messageId,
					type: "chat.message",
					source: platform,
					platform,
					userId: input.viewerId,
					username: viewerName,
					text: message,
					actor: {
						id: input.viewerId || "",
						name: viewerName,
						displayName: viewerName,
						badges,
					},
					payload: {
						message,
						isModerator: Boolean(input.isModerator),
						isMember: Boolean(input.isMember),
						isOwner: Boolean(input.isOwner),
					},
					badges,
					receivedAt: new Date().toISOString(),
					deliveryMode: "decisionOnly",
				}),
			})

			if (!response.ok) throw new Error(`Moderation docker rejected decision request with HTTP ${response.status}`)

			const payload = (await response.json()) as { moderation?: Record<string, unknown> }
			this.status.processedMessages += 1
			this.status.lastEventAt = new Date().toISOString()
			this.status.statusMessage = `Moderated ${platform} message through moderation docker.`
			return this.toActionResult({ messageId, ...(payload.moderation ?? {}) })
		} catch (error) {
			this.status.health = "error"
			this.status.statusMessage = error instanceof Error ? error.message : String(error)
			this.logger.error("Failed to moderate chat message.", error)
			return this.toActionResult({
				messageId,
				verdict: "error",
				status: "error",
				confidence: 0,
				category: "error",
				reason: this.status.statusMessage,
				backendError: true,
				errorMessage: this.status.statusMessage,
			})
		}
	}

	async getQueue(): Promise<ModerationQueueState> {
		const response = await fetch(this.joinUrl(this.settings.apiBaseUrl, "/api/moderation/queue"), {
			headers: this.authHeaders(),
		})
		if (!response.ok) throw new Error(`Queue request failed with HTTP ${response.status}`)
		return (await response.json()) as ModerationQueueState
	}

	async requestOverride(request: ModerationOverrideRequest): Promise<ModerationQueueState> {
		const response = await fetch(this.joinUrl(this.settings.apiBaseUrl, "/v1/overrides"), {
			method: "POST",
			headers: this.jsonHeaders(),
			body: JSON.stringify(request),
		})
		if (!response.ok) throw new Error(`Override request failed with HTTP ${response.status}`)
		return this.getQueue()
	}

	async sendTestMessage() {
		await this.forwardChatMessage({
			id: `showrunner-test-${Date.now()}`,
			platform: "showrunner",
			source: "showrunner",
			receivedAt: new Date().toISOString(),
			actor: {
				id: "showrunner-test",
				name: "showrunner-test",
				displayName: "ShowRunner Test",
				badges: ["test"],
			},
			payload: {
				message: "ShowRunner moderation docker test event.",
			},
		})
		return this.getStatus()
	}

	private normalizeSettings(settings: Partial<ModerationSettings>): ModerationSettings {
		return {
			enabled: Boolean(settings.enabled),
			apiBaseUrl: this.normalizeUrl(settings.apiBaseUrl, DEFAULT_SETTINGS.apiBaseUrl),
			apiToken: String(settings.apiToken || ""),
			dashboardWsUrl: this.normalizeUrl(settings.dashboardWsUrl, DEFAULT_SETTINGS.dashboardWsUrl),
			forwardYouTube: settings.forwardYouTube ?? DEFAULT_SETTINGS.forwardYouTube,
		}
	}

	private normalizeUrl(value: unknown, fallback: string) {
		const next = String(value || "").trim()
		return next || fallback
	}

	private connectDashboardSocket() {
		this.clearReconnectTimer()
		this.closeSocket()

		if (!this.settings.enabled) {
			this.status.connected = false
			return
		}

		try {
			const socket = new WebSocket(this.withToken(this.settings.dashboardWsUrl))
			this.socket = socket

			socket.on("open", () => {
				this.status.connected = true
				this.status.statusMessage = "Connected to moderation dashboard websocket."
			})

			socket.on("message", (data) => this.handleDashboardMessage(data.toString()))
			socket.on("error", (error) => {
				this.status.connected = false
				this.status.statusMessage = error.message
				this.logger.error("Moderation websocket error.", error)
			})
			socket.on("close", () => {
				this.status.connected = false
				this.scheduleReconnect()
			})
		} catch (error) {
			this.status.connected = false
			this.status.statusMessage = error instanceof Error ? error.message : String(error)
			this.scheduleReconnect()
		}
	}

	private handleDashboardMessage(raw: string) {
		try {
			const packet = JSON.parse(raw) as {
				verdict?: string
				status?: string
				type?: string
				eventType?: string
				messageId?: string
				id?: string
			}
			const decision = String(packet.verdict || packet.status || "").toLowerCase()
			if (decision === "allow" || decision === "approved") this.status.approvedMessages += 1
			if (decision === "block" || decision === "blocked" || decision === "rejected") this.status.blockedMessages += 1
			if (decision === "flag" || decision === "flagged" || decision === "pending") this.status.flaggedMessages += 1
			this.status.lastDecision = decision || packet.type || packet.eventType || "dashboard.event"
			this.status.lastEventAt = new Date().toISOString()
			this.recentDecisions.unshift({
				decision: this.status.lastDecision,
				eventType: packet.type || packet.eventType || "dashboard.event",
				messageId: packet.messageId || packet.id,
				receivedAt: this.status.lastEventAt,
			})
			if (this.recentDecisions.length > 10) this.recentDecisions.pop()
		} catch (error) {
			this.logger.log("Ignoring non-JSON moderation websocket payload.", raw, error)
		}
	}

	private scheduleReconnect() {
		if (!this.settings.enabled || this.reconnectTimer) return
		this.logger.log("Scheduling moderation websocket reconnect in 5s")
		this.reconnectTimer = setTimeout(() => {
			this.reconnectTimer = undefined
			this.connectDashboardSocket()
		}, 5000)
	}

	private clearReconnectTimer() {
		if (!this.reconnectTimer) return
		clearTimeout(this.reconnectTimer)
		this.reconnectTimer = undefined
	}

	private closeSocket() {
		if (!this.socket) return
		try {
			this.socket.removeAllListeners()
			this.socket.close()
		} catch (err) {
			this.logger.error("Error closing moderation websocket", err)
		}
		this.socket = undefined
	}

	private isSocketConnected() {
		return this.socket?.readyState === WebSocket.OPEN
	}

	private joinUrl(baseUrl: string, path: string) {
		const url = new URL(path, baseUrl.endsWith("/") ? baseUrl : `${baseUrl}/`)
		return url.toString()
	}

	private jsonHeaders() {
		return { "content-type": "application/json", ...this.authHeaders() }
	}

	private authHeaders(): Record<string, string> {
		if (this.settings.apiToken) return { authorization: `Bearer ${this.settings.apiToken}` }
		return {}
	}

	private withToken(value: string) {
		if (!this.settings.apiToken) return value
		const url = new URL(value)
		url.searchParams.set("token", this.settings.apiToken)
		return url.toString()
	}

	private parseBadges(value: unknown) {
		if (Array.isArray(value)) return value.map((badge) => String(badge)).filter(Boolean)
		return String(value || "")
			.split(",")
			.map((badge) => badge.trim())
			.filter(Boolean)
	}

	private toActionResult(payload: Record<string, unknown>): ModerationActionResult {
		const verdict = String(payload.verdict || "flag").toLowerCase()
		const status = String(payload.status || "").toLowerCase()
		const backendError = Boolean(payload.backendError) || verdict === "error" || status === "error"
		return {
			verdict,
			status:
				status ||
				(verdict === "allow"
					? "approved"
					: verdict === "block"
						? "blocked"
						: verdict === "disabled"
							? "disabled"
							: backendError
								? "error"
								: "flagged"),
			confidence: Number(payload.confidence ?? 0),
			category: String(payload.category || "unknown"),
			reason: String(payload.reason || ""),
			messageId: String(payload.messageId || ""),
			approved: verdict === "allow",
			blocked: verdict === "block",
			flagged: !backendError && verdict === "flag",
			backendError,
			errorMessage: String(payload.errorMessage || (backendError ? payload.reason || "" : "")),
		}
	}
}
