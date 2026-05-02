import { definePlugin } from "ShowRunner-core"

import { setupOverlayResources } from "./overlay-resource"
import { setupWebsockets } from "./websocket-bridge"

import { OverlayTextStyle } from "ShowRunner-plugin-overlays-shared"
import { setupEmoteBouncer } from "./emote-bouncer"
import { setupAlerts } from "./alerts"
import { setupChatFeed } from "./chat-feed"
import { setupPaidAlert } from "./paid-alert"
import { setupSceneEvents } from "./scene-events"
import { setupShaderPresets } from "./shader-presets"

export default definePlugin(
	{
		id: "overlays",
		name: "Overlays",
		description: "Overlay Plugin",
		color: "#CC63A2",
		icon: "mdi mdi-web",
	},
	() => {
		//Do not remove, forces bundler to init Overlay-Shared module
		OverlayTextStyle

		setupOverlayResources()
		setupAlerts()
		setupWebsockets()
		setupEmoteBouncer()
		setupChatFeed()
		setupPaidAlert()
		setupSceneEvents()
		setupShaderPresets()
	}
)

export { OverlayWebsocketService, handleWidgetRPC } from "./websocket-bridge"
