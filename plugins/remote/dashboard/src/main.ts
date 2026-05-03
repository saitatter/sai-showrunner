import { definePluginDashboard } from "showrunner-dashboard-core"

import Button from "./widgets/Button.vue"

export default definePluginDashboard({
	id: "remote",
	widgets: [Button],
})
