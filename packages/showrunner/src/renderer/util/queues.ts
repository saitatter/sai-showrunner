import { ResourceSchemaEdit, useResourceStore } from "showrunner-ui-core"
import { Duration } from "showrunner-schema"

export function initializeQueues() {
	const resourceStore = useResourceStore()

	resourceStore.registerConfigSchema("ActionQueue", {
		type: Object,
		properties: {
			name: { type: String, name: "Name", required: true },
			paused: { type: Boolean, name: "Paused", required: true, default: false },
			gap: { type: Duration, name: "Gap", required: true, default: 0 },
			timeout: { type: Duration, name: "Automation Timeout", required: true, default: 30 },
		},
	})
	resourceStore.registerEditComponent("ActionQueue", ResourceSchemaEdit)
	resourceStore.registerCreateComponent("ActionQueue", ResourceSchemaEdit)
}
