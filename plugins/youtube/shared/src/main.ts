export interface YouTubeActor {
	id: string
	name: string
	displayName: string
	avatarUrl?: string
}

export interface YouTubeChatMessage {
	id: string
	type: "youtube.chat.message"
	platform: "youtube"
	receivedAt: string
	actor: YouTubeActor
	payload: {
		message: string
		isModerator: boolean
		isMember: boolean
		isOwner: boolean
	}
}

export interface YouTubePaidEvent {
	id: string
	viewerId: string
	viewerName: string
	message: string
	amountMicros: number
	currency: string
}

export interface YouTubeMembershipEvent {
	id: string
	viewerId: string
	viewerName: string
	message: string
	eventType: "newSponsor" | "memberMilestone" | "membershipGift" | "giftMembershipReceived"
	memberLevelName?: string
	memberMonth?: number
}

export interface YouTubeBroadcastState {
	id?: string
	title?: string
	status: "unknown" | "offline" | "live"
	liveChatId?: string
}

export interface YouTubeConnectionState {
	accountName?: string
	channelId?: string
	status: "disconnected" | "connecting" | "connected" | "error" | "quotaLimited"
	statusMessage?: string
}

export interface YouTubeSettings {
	clientId: string
	scopes: string[]
	autoStartLiveChat: boolean
}

export interface YouTubeSecrets {
	clientSecret?: string
	accessToken?: string
	refreshToken?: string
	expiresAt?: number
	scope?: string
	tokenType?: string
}
