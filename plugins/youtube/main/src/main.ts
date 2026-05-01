import {
	definePlugin,
	defineRendererCallable,
	defineState,
	defineTransformTrigger,
	defineTrigger,
	onLoad,
	showrunnerChatModerationEvents,
	usePluginLogger,
} from "castmate-core"
import { Command, getCommandDataSchema, matchAndParseCommand } from "castmate-schema"
import { YouTubeBroadcastState, YouTubeChatMessage, YouTubeConnectionState } from "castmate-plugin-youtube-shared"
import { YouTubeAuthService } from "./youtube-auth"
import { YouTubeLiveChatService } from "./youtube-live-chat"

const disconnectedState: YouTubeConnectionState = {
	status: "disconnected",
	statusMessage: "YouTube OAuth is not configured yet.",
}

const offlineBroadcast: YouTubeBroadcastState = {
	status: "unknown",
}

export default definePlugin(
	{
		id: "youtube",
		name: "YouTube",
		description: "Provides YouTube Live triggers for chat, memberships, and paid messages.",
		icon: "mdi mdi-youtube",
		color: "#FF0033",
	},
	() => {
		const logger = usePluginLogger()
		const auth = new YouTubeAuthService()
		let liveChat: YouTubeLiveChatService
		const connection = defineState("connection", {
			type: Object,
			name: "Connection",
			properties: {
				accountName: { type: String, name: "Account Name" },
				channelId: { type: String, name: "Channel ID" },
				status: { type: String, name: "Status", required: true, default: "disconnected" },
				statusMessage: { type: String, name: "Status Message" },
			},
		})
		const broadcast = defineState("broadcast", {
			type: Object,
			name: "Broadcast",
			properties: {
				id: { type: String, name: "Broadcast ID" },
				title: { type: String, name: "Title" },
				status: { type: String, name: "Status", required: true, default: "unknown" },
				liveChatId: { type: String, name: "Live Chat ID" },
			},
		})
		const latestMessage = defineState("latestMessage", {
			type: Object,
			name: "Latest Message",
			properties: {
				id: { type: String, name: "Message ID" },
				author: { type: String, name: "Author" },
				message: { type: String, name: "Message" },
				receivedAt: { type: String, name: "Received At" },
			},
		})

		const chatMessage = defineTrigger({
			id: "chatMessage",
			name: "Chat Message",
			description: "Triggers when a YouTube live chat message is received.",
			icon: "mdi mdi-message-text",
			config: {
				type: Object,
				properties: {},
			},
			context: {
				type: Object,
				properties: {
					viewerId: { type: String, required: true, name: "Viewer ID", default: "youtube-channel-id" },
					viewerName: { type: String, required: true, name: "Viewer Name", default: "Viewer Name" },
					message: { type: String, required: true, name: "Message", default: "Hello from YouTube" },
					messageId: { type: String, required: true, name: "Message ID", default: "youtube-message-id", view: false },
					avatarUrl: { type: String, name: "Avatar URL", default: "" },
					isModerator: { type: Boolean, required: true, name: "Moderator", default: false },
					isMember: { type: Boolean, required: true, name: "Member", default: false },
					isOwner: { type: Boolean, required: true, name: "Owner", default: false },
				},
			},
			async handle() {
				return true
			},
		})

		const superChat = defineTrigger({
			id: "superChat",
			name: "Super Chat",
			description: "Triggers when a YouTube Super Chat is received.",
			icon: "mdi mdi-currency-usd",
			config: {
				type: Object,
				properties: {},
			},
			context: {
				type: Object,
				properties: {
					viewerName: { type: String, required: true, name: "Viewer Name", default: "Viewer Name" },
					message: { type: String, required: true, name: "Message", default: "Thanks for the stream!" },
					amountMicros: { type: Number, required: true, name: "Amount Micros", default: 1000000 },
					currency: { type: String, required: true, name: "Currency", default: "USD" },
				},
			},
			async handle() {
				return true
			},
		})

		const superSticker = defineTrigger({
			id: "superSticker",
			name: "Super Sticker",
			description: "Triggers when a YouTube Super Sticker is received.",
			icon: "mdi mdi-sticker",
			config: {
				type: Object,
				properties: {},
			},
			context: {
				type: Object,
				properties: {
					viewerName: { type: String, required: true, name: "Viewer Name", default: "Viewer Name" },
					message: { type: String, required: true, name: "Sticker", default: "Super Sticker" },
					amountMicros: { type: Number, required: true, name: "Amount Micros", default: 1000000 },
					currency: { type: String, required: true, name: "Currency", default: "USD" },
				},
			},
			async handle() {
				return true
			},
		})

		const membership = defineTrigger({
			id: "membership",
			name: "Membership",
			description: "Triggers when a YouTube membership event is received.",
			icon: "mdi mdi-account-star",
			config: {
				type: Object,
				properties: {},
			},
			context: {
				type: Object,
				properties: {
					viewerName: { type: String, required: true, name: "Viewer Name", default: "Viewer Name" },
					message: { type: String, required: true, name: "Message", default: "Thanks for becoming a member!" },
					eventType: { type: String, required: true, name: "Event Type", default: "newSponsor" },
					memberLevelName: { type: String, name: "Member Level", default: "Member" },
					memberMonth: { type: Number, name: "Member Month", default: 1 },
				},
			},
			async handle() {
				return true
			},
		})

		const chatCommand = defineTransformTrigger({
			id: "chatCommand",
			name: "Chat Command",
			description: "Triggers when a YouTube live chat message matches a command.",
			icon: "mdi mdi-message-processing",
			config: {
				type: Object,
				properties: {
					command: {
						type: Command,
						name: "Command",
						required: true,
					},
				},
			},
			invokeContext: {
				type: Object,
				properties: {
					viewerId: { type: String, required: true, name: "Viewer ID", default: "youtube-channel-id" },
					viewerName: { type: String, required: true, name: "Viewer Name", default: "Viewer Name" },
					message: { type: String, required: true, name: "Message", default: "!hello chat" },
					messageId: { type: String, required: true, name: "Message ID", default: "youtube-message-id", view: false },
					avatarUrl: { type: String, name: "Avatar URL", default: "" },
					isModerator: { type: Boolean, required: true, name: "Moderator", default: false },
					isMember: { type: Boolean, required: true, name: "Member", default: false },
					isOwner: { type: Boolean, required: true, name: "Owner", default: false },
				},
			},
			async context(config) {
				return {
					type: Object,
					properties: {
						viewerId: { type: String, required: true, name: "Viewer ID", default: "youtube-channel-id" },
						viewerName: { type: String, required: true, name: "Viewer Name", default: "Viewer Name" },
						message: { type: String, required: true, name: "Message", default: "!hello chat" },
						messageId: { type: String, required: true, name: "Message ID", default: "youtube-message-id", view: false },
						avatarUrl: { type: String, name: "Avatar URL", default: "" },
						isModerator: { type: Boolean, required: true, name: "Moderator", default: false },
						isMember: { type: Boolean, required: true, name: "Member", default: false },
						isOwner: { type: Boolean, required: true, name: "Owner", default: false },
						...getCommandDataSchema(config.command).properties,
					},
				}
			},
			async handle(config, context) {
				const matchResult = await matchAndParseCommand(context.message, config.command)
				if (matchResult == null) return undefined
				return {
					...context,
					...matchResult,
				}
			},
		})

		defineRendererCallable("getStatus", async () => ({
			connection: connection.value,
			broadcast: broadcast.value,
			latestMessage: latestMessage.value,
			settings: auth.getSettings(),
			liveChatRunning: liveChat?.isRunning ?? false,
		}))

		defineRendererCallable("saveSettings", async (settings: { clientId?: string; clientSecret?: string; autoStartLiveChat?: boolean }) => {
			await auth.saveSettings({
				clientId: settings.clientId?.trim() || "",
				clientSecret: settings.clientSecret,
				autoStartLiveChat: settings.autoStartLiveChat,
			})
			return auth.getSettings()
		})

		defineRendererCallable("connect", async () => {
			connection.value = {
				...connection.value,
				status: "connecting",
				statusMessage: "Opening Google login...",
			}

			try {
				const profile = await auth.login()
				connection.value = {
					accountName: profile.title,
					channelId: profile.channelId,
					status: "connected",
					statusMessage: "Connected to YouTube.",
				}
				return connection.value
			} catch (error) {
				connection.value = {
					...connection.value,
					status: "error",
					statusMessage: error instanceof Error ? error.message : String(error),
				}
				throw error
			}
		})

		defineRendererCallable("disconnect", async () => {
			liveChat?.stop()
			await auth.clear()
			connection.value = disconnectedState
			broadcast.value = offlineBroadcast
			return connection.value
		})

		defineRendererCallable("startLiveChat", async () => {
			connection.value = {
				...connection.value,
				statusMessage: "Starting YouTube live chat ingest...",
			}
			try {
				await liveChat.start()
			} catch (error) {
				connection.value = {
					...connection.value,
					statusMessage: error instanceof Error ? error.message : String(error),
				}
				throw error
			}
			return {
				connection: connection.value,
				broadcast: broadcast.value,
			}
		})

		defineRendererCallable("discoverBroadcast", async () => {
			connection.value = {
				...connection.value,
				statusMessage: "Discovering active YouTube broadcast...",
			}
			const nextBroadcast = await liveChat.discoverActiveBroadcast()
			broadcast.value = nextBroadcast
			connection.value = {
				...connection.value,
				statusMessage:
					nextBroadcast.status === "live"
						? "Active YouTube live chat discovered."
						: nextBroadcast.status === "unknown"
							? "A live broadcast was found, but live chat is not available yet."
							: "No active YouTube broadcast was found.",
			}
			return {
				connection: connection.value,
				broadcast: broadcast.value,
			}
		})

		defineRendererCallable("stopLiveChat", async () => {
			liveChat.stop()
			connection.value = {
				...connection.value,
				statusMessage: "YouTube live chat ingest stopped.",
			}
			return connection.value
		})

		defineRendererCallable("simulateChatMessage", async () => {
			const event: YouTubeChatMessage = {
				id: `demo-${Date.now()}`,
				type: "youtube.chat.message",
				platform: "youtube",
				receivedAt: new Date().toISOString(),
				actor: {
					id: "demo-viewer",
					name: "demo-viewer",
					displayName: "Demo Viewer",
					avatarUrl: "",
				},
				payload: {
					message: "YouTube plugin scaffold is alive.",
					isModerator: false,
					isMember: false,
					isOwner: false,
				},
			}

			latestMessage.value = {
				id: event.id,
				author: event.actor.displayName,
				message: event.payload.message,
				receivedAt: event.receivedAt,
			}

			await forwardToModeration(event)
			await chatMessage({
				viewerId: event.actor.id,
				viewerName: event.actor.displayName,
				message: event.payload.message,
				messageId: event.id,
				avatarUrl: event.actor.avatarUrl || "",
				isModerator: event.payload.isModerator,
				isMember: event.payload.isMember,
				isOwner: event.payload.isOwner,
			})

			return event
		})

		onLoad(async () => {
			await auth.initialize()
			liveChat = new YouTubeLiveChatService(auth, {
				onBroadcast(nextBroadcast) {
					broadcast.value = nextBroadcast
				},
				async onMessage(event) {
					latestMessage.value = {
						id: event.id,
						author: event.actor.displayName,
						message: event.payload.message,
						receivedAt: event.receivedAt,
					}
					await forwardToModeration(event)
					await chatMessage({
						viewerId: event.actor.id,
						viewerName: event.actor.displayName,
						message: event.payload.message,
						messageId: event.id,
						avatarUrl: event.actor.avatarUrl || "",
						isModerator: event.payload.isModerator,
						isMember: event.payload.isMember,
						isOwner: event.payload.isOwner,
					})
					await chatCommand({
						viewerId: event.actor.id,
						viewerName: event.actor.displayName,
						message: event.payload.message,
						messageId: event.id,
						avatarUrl: event.actor.avatarUrl || "",
						isModerator: event.payload.isModerator,
						isMember: event.payload.isMember,
						isOwner: event.payload.isOwner,
					})
				},
				async onSuperChat(event) {
					await superChat({
						viewerName: event.viewerName,
						message: event.message,
						amountMicros: event.amountMicros,
						currency: event.currency,
					})
				},
				async onSuperSticker(event) {
					await superSticker({
						viewerName: event.viewerName,
						message: event.message,
						amountMicros: event.amountMicros,
						currency: event.currency,
					})
				},
				async onMembership(event) {
					await membership({
						viewerName: event.viewerName,
						message: event.message,
						eventType: event.eventType,
						memberLevelName: event.memberLevelName,
						memberMonth: event.memberMonth,
					})
				},
				onError(error) {
					connection.value = {
						...connection.value,
						status: error.message.includes("quota") ? "quotaLimited" : connection.value.status,
						statusMessage: error.message,
					}
					logger.error("YouTube live chat ingest failed.", error)
				},
			})
			connection.value = disconnectedState
			broadcast.value = offlineBroadcast
			try {
				if (auth.hasUsableToken || auth.hasStoredRefreshToken) {
					const profile = await auth.fetchProfile()
					connection.value = {
						accountName: profile.title,
						channelId: profile.channelId,
						status: "connected",
						statusMessage: "Connected to YouTube.",
					}
				}
			} catch (error) {
				connection.value = {
					status: "error",
					statusMessage: error instanceof Error ? error.message : String(error),
				}
			}
			logger.log("YouTube plugin scaffold loaded.")
		})

		async function forwardToModeration(event: YouTubeChatMessage) {
			try {
				await showrunnerChatModerationEvents.run({
					id: event.id,
					platform: event.platform,
					source: "youtube",
					receivedAt: event.receivedAt,
					actor: {
						...event.actor,
						badges: [
							...(event.payload.isOwner ? ["owner"] : []),
							...(event.payload.isModerator ? ["moderator"] : []),
							...(event.payload.isMember ? ["member"] : []),
						],
					},
					payload: event.payload,
				})
			} catch (error) {
				logger.warn("Failed to forward YouTube message to moderation docker.", error)
			}
		}
	}
)
