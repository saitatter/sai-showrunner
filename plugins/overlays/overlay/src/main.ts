import { defineOverlayPlugin } from "showrunner-overlay-core"
import { overlayWidgets } from "./widgets"

export default defineOverlayPlugin({
	pluginId: "overlays",
	widgets: overlayWidgets,
})
