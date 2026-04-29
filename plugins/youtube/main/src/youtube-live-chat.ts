import { YouTubeBroadcastState, YouTubeChatMessage } from "castmate-plugin-youtube-shared"
import { YouTubeAuthService } from "./youtube-auth"

interface YouTubeLiveBroadcastsResponse {
	items?: Array<{
		id: string
		snippet?: {
			title?: string
			liveChatId?: string
		}
	}>
}

interface YouTubeLiveChatMessagesResponse {
	nextPageToken?: string
	pollingIntervalMillis?: number
	offlineAt?: string
	items?: YouTubeLiveChatMessageResource[]
}

interface YouTubeLiveChatMessageResource {
	id: string
	snippet?: {
		type?: string
		publishedAt?: string
		displayMessage?: string
		superChatDetails?: {
			amountMicros?: string
			currency?: string
			userComment?: string
		}
		superStickerDetails?: {
			amountMicros?: string
			currency?: string
			superStickerMetadata?: {
				altText?: string
			}
		}
	}
	authorDetails?: {
		channelId?: string
		channelUrl?: string
		displayName?: string
		profileImageUrl?: string
		isChatOwner?: boolean
		isChatSponsor?: boolean
		isChatModerator?: boolean
	}
}

export interface YouTubePaidMessage {
	id: string
	viewerId: string
	viewerName: string
	message: string
	amountMicros: number
	currency: string
}

export class YouTubeLiveChatService {
	private nextPageToken: string | undefined
	private timer: NodeJS.Timeout | undefined
	private stopped = true

	constructor(
		private auth: YouTubeAuthService,
		private handlers: {
			onBroadcast: (broadcast: YouTubeBroadcastState) => void
			onMessage: (message: YouTubeChatMessage) => Promise<void> | void
			onSuperChat: (message: YouTubePaidMessage) => Promise<void> | void
			onError: (error: Error) => void
		}
	) {}

	get isRunning() {
		return !this.stopped
	}

	async discoverActiveBroadcast(): Promise<YouTubeBroadcastState> {
		const url = new URL("https://www.googleapis.com/youtube/v3/liveBroadcasts")
		url.searchParams.set("part", "snippet")
		url.searchParams.set("broadcastStatus", "active")
		url.searchParams.set("mine", "true")
		const data = await this.auth.authorizedFetch<YouTubeLiveBroadcastsResponse>(url)
		const broadcast = data.items?.[0]

		if (!broadcast) {
			return { status: "offline" }
		}

		return {
			id: broadcast.id,
			title: broadcast.snippet?.title,
			liveChatId: broadcast.snippet?.liveChatId,
			status: broadcast.snippet?.liveChatId ? "live" : "unknown",
		}
	}

	async start() {
		this.stop()
		this.stopped = false
		this.nextPageToken = undefined

		const broadcast = await this.discoverActiveBroadcast()
		this.handlers.onBroadcast(broadcast)
		if (!broadcast.liveChatId) {
			throw new Error("No active YouTube live chat was found.")
		}

		await this.poll(broadcast.liveChatId)
	}

	stop() {
		this.stopped = true
		if (this.timer) {
			clearTimeout(this.timer)
			this.timer = undefined
		}
	}

	private async poll(liveChatId: string) {
		if (this.stopped) return

		try {
			const url = new URL("https://www.googleapis.com/youtube/v3/liveChat/messages")
			url.searchParams.set("part", "snippet,authorDetails")
			url.searchParams.set("liveChatId", liveChatId)
			url.searchParams.set("maxResults", "200")
			if (this.nextPageToken) url.searchParams.set("pageToken", this.nextPageToken)

			const data = await this.auth.authorizedFetch<YouTubeLiveChatMessagesResponse>(url)
			this.nextPageToken = data.nextPageToken

			for (const item of data.items || []) {
				await this.handleMessage(item)
			}

			if (data.offlineAt) {
				this.handlers.onBroadcast({ status: "offline" })
				this.stop()
				return
			}

			const delay = Math.max(1000, data.pollingIntervalMillis || 5000)
			this.timer = setTimeout(() => void this.poll(liveChatId), delay)
		} catch (error) {
			this.handlers.onError(error instanceof Error ? error : new Error(String(error)))
			this.timer = setTimeout(() => void this.poll(liveChatId), 15000)
		}
	}

	private async handleMessage(item: YouTubeLiveChatMessageResource) {
		const author = item.authorDetails
		const snippet = item.snippet
		const viewerId = author?.channelId || "unknown"
		const viewerName = author?.displayName || viewerId
		const message = snippet?.displayMessage || snippet?.superChatDetails?.userComment || ""

		const normalized: YouTubeChatMessage = {
			id: item.id,
			type: "youtube.chat.message",
			platform: "youtube",
			receivedAt: snippet?.publishedAt || new Date().toISOString(),
			actor: {
				id: viewerId,
				name: viewerId,
				displayName: viewerName,
				avatarUrl: author?.profileImageUrl,
			},
			payload: {
				message,
				isModerator: Boolean(author?.isChatModerator),
				isMember: Boolean(author?.isChatSponsor),
				isOwner: Boolean(author?.isChatOwner),
			},
		}

		await this.handlers.onMessage(normalized)

		if (snippet?.type === "superChatEvent" && snippet.superChatDetails) {
			await this.handlers.onSuperChat({
				id: item.id,
				viewerId,
				viewerName,
				message,
				amountMicros: Number(snippet.superChatDetails.amountMicros || 0),
				currency: snippet.superChatDetails.currency || "USD",
			})
		}
	}
}
