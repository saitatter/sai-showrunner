import { ModerationChatEvent, ModerationSettings, ModerationStatus } from "castmate-plugin-moderation-shared"

const DEFAULT_SETTINGS: ModerationSettings = {
	enabled: false,
	apiBaseUrl: "http://localhost:8787",
	dashboardWsUrl: "ws://localhost:8787/ws?channel=dashboard",
	forwardYouTube: true,
}

export class ModerationService {
	private static instance: ModerationService | undefined

	static getInstance() {
		this.instance ??= new ModerationService()
		return this.instance
	}

	async initialize() {}

	getStatus(): ModerationStatus {
		return {
			...DEFAULT_SETTINGS,
			connected: false,
			health: "unknown",
			processedMessages: 0,
			approvedMessages: 0,
			blockedMessages: 0,
			flaggedMessages: 0,
		}
	}

	async saveSettings(_settings: Partial<ModerationSettings>) {
		return this.getStatus()
	}

	async checkHealth() {
		return this.getStatus()
	}

	async reconnect() {
		return this.getStatus()
	}

	async forwardChatMessage(_event: ModerationChatEvent) {}
}
