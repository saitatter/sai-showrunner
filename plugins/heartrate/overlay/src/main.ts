import { defineOverlayPlugin } from "showrunner-overlay-core"
import { heartRateGraphWidget, heartRateWidget, heartRateZoneWidget } from "./widgets"

export default defineOverlayPlugin({
	pluginId: "heartrate",
	widgets: [heartRateWidget, heartRateZoneWidget, heartRateGraphWidget],
})
