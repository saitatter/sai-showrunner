import { definePluginOverlays } from "showrunner-overlay-core"

import WheelVue from "./widgets/Wheel.vue"

export default definePluginOverlays({
	id: "random",
	widgets: [WheelVue],
})
