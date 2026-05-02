import { defineAction } from "ShowRunner-core"
import { OverlayWidget } from "ShowRunner-plugin-overlays-shared"
import { OverlayWebsocketService } from "./websocket-bridge"

export function setupSceneEvents() {
	defineAction({
		id: "beginSceneOverlay",
		name: "Begin Scene Overlay",
		description: "Publishes a scene begin event to Scene Banner and future scene overlay widgets.",
		icon: "mdi mdi-play-box-outline",
		config: {
			type: Object,
			properties: {
				targetWidget: { type: OverlayWidget, name: "Target Scene Widget" },
				sceneKey: { type: String, name: "Scene Key", template: true, default: "main" },
				title: { type: String, name: "Title", template: true, default: "Starting Soon" },
				subtitle: { type: String, name: "Subtitle", template: true, default: "" },
				accentColor: { type: String, name: "Accent Color", template: true, default: "#9146ff" },
			},
		},
		async invoke(config) {
			sendSceneEvent("scene.begin", config)
		},
	})

	defineAction({
		id: "endSceneOverlay",
		name: "End Scene Overlay",
		description: "Publishes a scene end event to Scene Banner and future scene overlay widgets.",
		icon: "mdi mdi-stop-circle-outline",
		config: {
			type: Object,
			properties: {
				targetWidget: { type: OverlayWidget, name: "Target Scene Widget" },
				sceneKey: { type: String, name: "Scene Key", template: true, default: "main" },
			},
		},
		async invoke(config) {
			sendSceneEvent("scene.end", config)
		},
	})
}

function sendSceneEvent(type: "scene.begin" | "scene.end", config: any) {
	OverlayWebsocketService.getInstance().sendOverlayMessage("showrunner_scene_event", {
		type,
		targetOverlayId: config.targetWidget?.overlayId || "",
		targetWidgetId: config.targetWidget?.widgetId || "",
		sceneKey: config.sceneKey || "main",
		title: config.title || "",
		subtitle: config.subtitle || "",
		accentColor: config.accentColor || "#9146ff",
	})
}
