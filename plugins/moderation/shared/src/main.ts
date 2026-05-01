export interface ModerationSettings {
	enabled: boolean
	apiBaseUrl: string
	dashboardWsUrl: string
	forwardYouTube: boolean
}

export interface ModerationStatus {
	enabled: boolean
	apiBaseUrl: string
	dashboardWsUrl: string
	forwardYouTube: boolean
	connected: boolean
	health: "unknown" | "healthy" | "error"
	statusMessage?: string
	processedMessages: number
	approvedMessages: number
	blockedMessages: number
	flaggedMessages: number
	lastEventAt?: string
	lastDecision?: string
}

export interface ModerationChatEvent {
	id: string
	platform: string
	source: string
	receivedAt: string
	actor: {
		id: string
		name: string
		displayName: string
		avatarUrl?: string
		badges?: string[]
	}
	payload: {
		message: string
		isModerator?: boolean
		isMember?: boolean
		isOwner?: boolean
	}
}
