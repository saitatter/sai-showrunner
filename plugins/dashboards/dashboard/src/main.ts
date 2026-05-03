import { definePluginDashboard } from "showrunner-dashboard-core"
import Label from "./widgets/Label.vue"

export default definePluginDashboard({
	id: "dashboards",
	widgets: [Label],
})
