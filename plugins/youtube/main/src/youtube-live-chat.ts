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

const SEARCH_DISCOVERY_CACHE_MS = 60_000

export class YouTubeLiveChatService {
	private nextPageToken: string | undefined
	private timer: NodeJS.Timeout | undefined
	private stopped = true
	private errorAttempts = 0
	private sessionId = 0
	private diagnostics = {
		estimatedQuotaUnits: 0,
		liveChatPolls: 0,
		searchDiscoveries: 0,
		lastApiError: undefined as string | undefined,
		lastApiErrorAt: undefined as string | undefined,
		nextRetryAt: undefined as string | undefined,
	}
	private searchDiscoveryCache:
		| {
				expiresAt: number
				result: YouTubeBroadcastState
		  }
		| undefined
	private searchDiscoveryPromise: Promise<YouTubeBroadcastState> | undefined

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

	getDiagnostics() {
		return {
			...this.diagnostics,
			searchDiscoveryCooldownUntil: this.searchDiscoveryCache?.expiresAt
				? new Date(this.searchDiscoveryCache.expiresAt).toISOString()
				: undefined,
			searchDiscoveryCached: Boolean(this.searchDiscoveryCache && this.searchDiscoveryCache.expiresAt > Date.now()),
			searchDiscoveryInFlight: Boolean(this.searchDiscoveryPromise),
		}
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
		const now = Date.now()
		if (this.searchDiscoveryCache && this.searchDiscoveryCache.expiresAt > now) {
			return this.searchDiscoveryCache.result
		}
		if (this.searchDiscoveryPromise) return this.searchDiscoveryPromise

		this.searchDiscoveryPromise = this.fetchSearchLive().finally(() => {
			this.searchDiscoveryPromise = undefined
		})

		const result = await this.searchDiscoveryPromise
		this.searchDiscoveryCache = {
			expiresAt: Date.now() + SEARCH_DISCOVERY_CACHE_MS,
			result,
		}
		return result
	}

	private async fetchSearchLive(): Promise<YouTubeBroadcastState> {
		this.diagnostics.searchDiscoveries += 1
		this.diagnostics.estimatedQuotaUnits += 100
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
		this.diagnostics.estimatedQuotaUnits += 1
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
		const sessionId = ++this.sessionId
		this.stopped = false
		this.nextPageToken = undefined

		const broadcast = await this.discoverActiveBroadcast()
		if (!this.isActiveSession(sessionId)) return
		this.handlers.onBroadcast(broadcast)
		if (!broadcast.liveChatId) {
			throw new Error("No active YouTube live chat was found.")
		}

		await this.poll(broadcast.liveChatId, sessionId)
	}

	stop() {
		this.stopped = true
		this.sessionId += 1
		if (this.timer) {
			clearTimeout(this.timer)
			this.timer = undefined
		}
	}

	private isActiveSession(sessionId: number) {
		return !this.stopped && this.sessionId === sessionId
	}

	private async poll(liveChatId: string, sessionId: number) {
		if (!this.isActiveSession(sessionId)) return

		try {
			const url = new URL("https://www.googleapis.com/youtube/v3/liveChat/messages")
			url.searchParams.set("part", "snippet,authorDetails")
			url.searchParams.set("liveChatId", liveChatId)
			url.searchParams.set("maxResults", "200")
			if (this.nextPageToken) url.searchParams.set("pageToken", this.nextPageToken)

			const data = await this.auth.authorizedFetch<YouTubeLiveChatMessagesResponse>(url)
			if (!this.isActiveSession(sessionId)) return
			this.diagnostics.liveChatPolls += 1
			this.diagnostics.estimatedQuotaUnits += 5
			this.diagnostics.nextRetryAt = undefined
			this.errorAttempts = 0
			this.nextPageToken = data.nextPageToken

			for (const item of data.items || []) {
				if (!this.isActiveSession(sessionId)) return
				await this.handleMessage(item)
			}

			if (data.offlineAt) {
				this.handlers.onBroadcast({ status: "offline" })
				this.stop()
				return
			}

			const delay = Math.max(1000, data.pollingIntervalMillis || 5000)
			this.timer = setTimeout(() => {
				this.poll(liveChatId, sessionId).catch((err) => this.handlers.onError(err instanceof Error ? err : new Error(String(err))))
			}, delay)
		} catch (error) {
			if (!this.isActiveSession(sessionId)) return
			const normalizedError = error instanceof Error ? error : new Error(String(error))
			this.diagnostics.lastApiError = normalizedError.message
			this.diagnostics.lastApiErrorAt = new Date().toISOString()
			const delay = Math.min(120000, 15000 * Math.pow(2, this.errorAttempts))
			this.errorAttempts += 1
			this.diagnostics.nextRetryAt = new Date(Date.now() + delay).toISOString()
			this.handlers.onError(normalizedError)
			this.timer = setTimeout(() => {
				this.poll(liveChatId, sessionId).catch((err) => this.handlers.onError(err instanceof Error ? err : new Error(String(err))))
			}, delay)
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
