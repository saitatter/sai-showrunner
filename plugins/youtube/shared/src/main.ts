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
