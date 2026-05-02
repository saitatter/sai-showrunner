import { definePluginDashboard } from "ShowRunner-dashboard-core"

import Button from "./widgets/Button.vue"

export default definePluginDashboard({
	id: "remote",
	widgets: [Button],
})
