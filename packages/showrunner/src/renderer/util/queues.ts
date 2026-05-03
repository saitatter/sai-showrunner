import { computed } from "vue"
import { ProjectItem } from "./../../../../../libs/showrunner-ui-core/src/project/project-store"
import { ResourceSchemaEdit, useDockingStore, useProjectStore, useResourceStore } from "showrunner-ui-core"
import QueuePage from "../components/queues/QueuePage.vue"
import { Duration } from "showrunner-schema"

export function initializeQueues() {
	const dockingStore = useDockingStore()
	const projectStore = useProjectStore()
	const resourceStore = useResourceStore()

	const projectItem = computed<ProjectItem>(() => {
		return {
			id: "queues",
			title: "Queues",
			icon: "mdi mdi-tray-full",
			open() {
				dockingStore.openPage("queues", "Queues", "mdi mdi-tray-full", QueuePage)
			},
		}
	})

	projectStore.registerProjectGroupItem(projectItem)

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
