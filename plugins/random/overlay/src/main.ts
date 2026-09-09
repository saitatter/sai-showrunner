import { defineOverlayPlugin } from "showrunner-overlay-core"
import { wheelWidget } from "./widgets"

export default defineOverlayPlugin({
	pluginId: "random",
	widgets: [wheelWidget],
})
