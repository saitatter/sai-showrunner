import { defineOverlayPlugin } from "showrunner-overlay-core"
import { heartRateWidget } from "./widgets"

export default defineOverlayPlugin({
	pluginId: "heartrate",
	widgets: [heartRateWidget],
})
