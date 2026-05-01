import { defineAction, definePlugin, defineRendererCallable, onLoad } from "castmate-core"
import { ModerationService } from "./moderation-service"

export { ModerationService } from "./moderation-service"

declare global {
	var __showrunnerModeration: ModerationService | undefined
}

export default definePlugin(
	{
		id: "moderation",
		name: "Moderation Docker",
		description: "Connects ShowRunner events to the SAI moderation docker.",
		icon: "mdi mdi-shield-check",
		color: "#20D6B5",
	},
	() => {
		const moderation = ModerationService.getInstance()
		globalThis.__showrunnerModeration = moderation

		defineRendererCallable("getStatus", async () => moderation.getStatus())
		defineRendererCallable("saveSettings", async (settings) => moderation.saveSettings(settings))
		defineRendererCallable("checkHealth", async () => moderation.checkHealth())
		defineRendererCallable("reconnect", async () => moderation.reconnect())
		defineRendererCallable("sendTestMessage", async () => moderation.sendTestMessage())
		defineRendererCallable("getQueue", async () => moderation.getQueue())
		defineRendererCallable("requestOverride", async (request) => moderation.requestOverride(request))

		defineAction({
			id: "moderateChatMessage",
			name: "Filter Chat Message",
			description: "Sends a chat message to moderation docker and returns the moderation decision.",
			icon: "mdi mdi-shield-search",
			config: {
				type: Object,
				properties: {
					platform: { type: String, name: "Platform", template: true, default: "twitch" },
					messageId: { type: String, name: "Message ID", template: true, default: "" },
					viewerId: { type: String, name: "Viewer ID", template: true, default: "" },
					viewerName: { type: String, name: "Viewer Name", template: true, default: "" },
					message: {
						type: String,
						name: "Message",
						template: true,
						required: true,
						default: "",
						multiLine: true,
					},
					badges: {
						type: String,
						name: "Badges",
						template: true,
						default: "",
						description: "Comma-separated badge names.",
					},
					isModerator: { type: Boolean, name: "Moderator", template: true, default: false },
					isMember: { type: Boolean, name: "Member", template: true, default: false },
					isOwner: { type: Boolean, name: "Owner", template: true, default: false },
				},
			},
			result: {
				type: Object,
				properties: {
					verdict: { type: String, name: "Verdict", required: true },
					status: { type: String, name: "Status", required: true },
					confidence: { type: Number, name: "Confidence", required: true },
					category: { type: String, name: "Category", required: true },
					reason: { type: String, name: "Reason", required: true },
					messageId: { type: String, name: "Message ID", required: true },
					approved: { type: Boolean, name: "Approved", required: true },
					blocked: { type: Boolean, name: "Blocked", required: true },
					flagged: { type: Boolean, name: "Flagged", required: true },
				},
			},
			async invoke(config) {
				return moderation.moderateChatMessage(config)
			},
		})

		onLoad(async () => {
			await moderation.initialize()
		})
	}
)
