import { defineAction } from "castmate-core"
import { OverlayWidget } from "castmate-plugin-overlays-shared"
import { OverlayWebsocketService } from "./websocket-bridge"

export function setupPaidAlert() {
	defineAction({
		id: "pushPaidAlert",
		name: "Push Paid Alert",
		description: "Pushes a paid message, donation, or membership-style alert to a Paid Alert overlay widget.",
		icon: "mdi mdi-cash-star",
		config: {
			type: Object,
			properties: {
				targetWidget: { type: OverlayWidget, name: "Target Paid Alert" },
				eventId: { type: String, name: "Event ID", template: true, default: "" },
				platform: { type: String, name: "Platform", template: true, default: "youtube" },
				viewerName: { type: String, name: "Viewer Name", template: true, default: "" },
				amount: { type: String, name: "Amount", template: true, default: "" },
				currency: { type: String, name: "Currency", template: true, default: "USD" },
				title: { type: String, name: "Title", template: true, default: "New Support" },
				message: { type: String, name: "Message", template: true, default: "", multiLine: true },
			},
		},
		async invoke(config) {
			OverlayWebsocketService.getInstance().sendOverlayMessage("showrunner_paid_alert", {
				targetOverlayId: config.targetWidget?.overlayId || "",
				targetWidgetId: config.targetWidget?.widgetId || "",
				id: config.eventId || `showrunner-paid-${Date.now()}`,
				platform: config.platform || "unknown",
				displayName: config.viewerName || "unknown",
				amount: config.amount || "",
				currency: config.currency || "",
				title: config.title || "New Support",
				message: config.message || "",
			})
		},
	})
}
