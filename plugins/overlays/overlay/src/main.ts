import { defineOverlayPlugin } from "showrunner-overlay-core"
import { overlayWidgetFactories } from "./widgets"

export default defineOverlayPlugin({
	pluginId: "overlays",
	widgets: overlayWidgetFactories,
})
