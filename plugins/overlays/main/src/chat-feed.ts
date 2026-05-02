import { defineAction } from "ShowRunner-core"
import { OverlayWidget } from "ShowRunner-plugin-overlays-shared"
import { OverlayWebsocketService } from "./websocket-bridge"

export function setupChatFeed() {
	defineAction({
		id: "pushChatMessage",
		name: "Push Chat Message",
		description: "Pushes an approved chat message to Chat Feed overlay widgets.",
		icon: "mdi mdi-chat-processing-outline",
		config: {
			type: Object,
			properties: {
				targetWidget: { type: OverlayWidget, name: "Target Chat Feed" },
				messageId: { type: String, name: "Message ID", template: true, default: "" },
				platform: { type: String, name: "Platform", template: true, default: "twitch" },
				viewerName: { type: String, name: "Viewer Name", template: true, default: "" },
				message: { type: String, name: "Message", template: true, required: true, default: "", multiLine: true },
				badges: {
					type: String,
					name: "Badges",
					template: true,
					default: "",
					description: "Comma-separated badge names.",
				},
			},
		},
		async invoke(config) {
			OverlayWebsocketService.getInstance().sendOverlayMessage("showrunner_chat_message", {
				targetOverlayId: config.targetWidget?.overlayId || "",
				targetWidgetId: config.targetWidget?.widgetId || "",
				id: config.messageId || `showrunner-chat-${Date.now()}`,
				platform: config.platform || "unknown",
				displayName: config.viewerName || "unknown",
				username: config.viewerName || "unknown",
				message: config.message || "",
				badges: config.badges || "",
			})
		},
	})
}
