import {
	YouTubeBroadcastState,
	YouTubeChatMessage,
	YouTubeMembershipEvent,
	YouTubePaidEvent,
} from "castmate-plugin-youtube-shared"
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

interface YouTubeSearchResponse {
	items?: Array<{
		id?: {
			videoId?: string
		}
		snippet?: {
			title?: string
		}
	}>
}

interface YouTubeVideosResponse {
	items?: Array<{
		id: string
		snippet?: {
			title?: string
			liveBroadcastContent?: string
		}
		liveStreamingDetails?: {
			activeLiveChatId?: string
			actualStartTime?: string
			actualEndTime?: string
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
		memberMilestoneChatDetails?: {
			memberMonth?: number
			memberLevelName?: string
			userComment?: string
		}
		newSponsorDetails?: {
			memberLevelName?: string
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

export class YouTubeLiveChatService {
	private nextPageToken: string | undefined
	private timer: NodeJS.Timeout | undefined
	private stopped = true

	constructor(
		private auth: YouTubeAuthService,
		private handlers: {
			onBroadcast: (broadcast: YouTubeBroadcastState) => void
			onMessage: (message: YouTubeChatMessage) => Promise<void> | void
			onSuperChat: (message: YouTubePaidEvent) => Promise<void> | void
			onSuperSticker: (message: YouTubePaidEvent) => Promise<void> | void
			onMembership: (message: YouTubeMembershipEvent) => Promise<void> | void
			onError: (error: Error) => void
		}
	) {}

	get isRunning() {
		return !this.stopped
	}

	async discoverActiveBroadcast(): Promise<YouTubeBroadcastState> {
		const broadcast = await this.discoverBroadcastManagerLive()
		if (broadcast.status === "live" || broadcast.liveChatId) return broadcast
		return this.discoverSearchLive()
	}

	private async discoverBroadcastManagerLive(): Promise<YouTubeBroadcastState> {
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

	private async discoverSearchLive(): Promise<YouTubeBroadcastState> {
		const searchUrl = new URL("https://www.googleapis.com/youtube/v3/search")
		searchUrl.searchParams.set("part", "snippet")
		searchUrl.searchParams.set("forMine", "true")
		searchUrl.searchParams.set("type", "video")
		searchUrl.searchParams.set("eventType", "live")
		searchUrl.searchParams.set("maxResults", "5")
		const searchData = await this.auth.authorizedFetch<YouTubeSearchResponse>(searchUrl)
		const videoIds = (searchData.items || []).map((item) => item.id?.videoId).filter(Boolean) as string[]

		if (!videoIds.length) {
			return { status: "offline" }
		}

		const videosUrl = new URL("https://www.googleapis.com/youtube/v3/videos")
		videosUrl.searchParams.set("part", "snippet,liveStreamingDetails")
		videosUrl.searchParams.set("id", videoIds.join(","))
		const videosData = await this.auth.authorizedFetch<YouTubeVideosResponse>(videosUrl)
		const video = videosData.items?.find((item) => item.liveStreamingDetails?.activeLiveChatId) || videosData.items?.[0]

		if (!video) {
			return { status: "offline" }
		}

		const liveChatId = video.liveStreamingDetails?.activeLiveChatId
		return {
			id: video.id,
			title: video.snippet?.title,
			liveChatId,
			status: liveChatId ? "live" : "unknown",
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
		const message =
			snippet?.displayMessage ||
			snippet?.superChatDetails?.userComment ||
			snippet?.memberMilestoneChatDetails?.userComment ||
			snippet?.superStickerDetails?.superStickerMetadata?.altText ||
			""

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

		if (snippet?.type === "superStickerEvent" && snippet.superStickerDetails) {
			await this.handlers.onSuperSticker({
				id: item.id,
				viewerId,
				viewerName,
				message,
				amountMicros: Number(snippet.superStickerDetails.amountMicros || 0),
				currency: snippet.superStickerDetails.currency || "USD",
			})
		}

		const membershipEventType = this.toMembershipEventType(snippet?.type)
		if (membershipEventType) {
			await this.handlers.onMembership({
				id: item.id,
				viewerId,
				viewerName,
				message,
				eventType: membershipEventType,
				memberLevelName: snippet?.memberMilestoneChatDetails?.memberLevelName || snippet?.newSponsorDetails?.memberLevelName,
				memberMonth: snippet?.memberMilestoneChatDetails?.memberMonth,
			})
		}
	}

	private toMembershipEventType(type?: string): YouTubeMembershipEvent["eventType"] | undefined {
		if (type === "newSponsorEvent") return "newSponsor"
		if (type === "memberMilestoneChatEvent") return "memberMilestone"
		if (type === "membershipGiftingEvent") return "membershipGift"
		if (type === "giftMembershipReceivedEvent") return "giftMembershipReceived"
		return undefined
	}
}
