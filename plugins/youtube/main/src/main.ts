import { definePlugin, defineRendererCallable, defineState, defineTrigger, onLoad, usePluginLogger } from "castmate-core"
import { YouTubeBroadcastState, YouTubeChatMessage, YouTubeConnectionState } from "castmate-plugin-youtube-shared"

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
				},
			},
			async handle() {
				return true
			},
		})

		defineTrigger({
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

		defineRendererCallable("getStatus", async () => ({
			connection: connection.value,
			broadcast: broadcast.value,
			latestMessage: latestMessage.value,
		}))

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

			await chatMessage({
				viewerId: event.actor.id,
				viewerName: event.actor.displayName,
				message: event.payload.message,
				messageId: event.id,
			})

			return event
		})

		onLoad(() => {
			connection.value = disconnectedState
			broadcast.value = offlineBroadcast
			logger.log("YouTube plugin scaffold loaded.")
		})
	}
)
