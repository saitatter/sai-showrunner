export interface ModerationSettings {
	enabled: boolean
	apiBaseUrl: string
	apiToken: string
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
	recentDecisions?: ModerationDecisionSummary[]
}

export interface ModerationDecisionSummary {
	decision: string
	eventType: string
	messageId?: string
	receivedAt: string
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

export interface ModerationQueueState {
	latest: ModerationQueueEntry[]
	pending: ModerationQueueEntry[]
	approved: ModerationQueueEntry[]
	rejected: ModerationQueueEntry[]
}

export interface ModerationQueueEntry {
	eventType: string
	messageId: string
	platform: string
	username: string
	text: string
	verdict: string
	confidence?: number
	category?: string
	reason?: string
	receivedAt?: string
}

export interface ModerationOverrideRequest {
	messageId: string
	action: "approve" | "block" | "falsePositive"
	operatorId: string
	reason: string
}

export interface ModerationActionInput {
	platform?: string
	messageId?: string
	viewerId?: string
	viewerName?: string
	message?: string
	badges?: string
	isModerator?: boolean
	isMember?: boolean
	isOwner?: boolean
}

export interface ModerationActionResult {
	verdict: string
	status: string
	confidence: number
	category: string
	reason: string
	messageId: string
	approved: boolean
	blocked: boolean
	flagged: boolean
	backendError: boolean
	errorMessage: string
}
