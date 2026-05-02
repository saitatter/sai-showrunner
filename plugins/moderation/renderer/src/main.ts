import { App, computed } from "vue"
import { ProjectGroup, useDockingStore, useProjectStore } from "ShowRunner-ui-core"
import ModerationPage from "./components/ModerationPage.vue"

export async function initPlugin(app: App<Element>) {
	const projectStore = useProjectStore()
	const dockingStore = useDockingStore()

	projectStore.registerProjectGroupChild(
		{
			id: "integrations",
			title: "Integrations",
			icon: "mdi mdi-connection",
		},
		computed<ProjectGroup>(() => ({
			id: "moderation",
			title: "Moderation",
			icon: "mdi mdi-shield-check",
			items: [
				{
					id: "moderation.docker",
					title: "Moderation Docker",
					icon: "mdi mdi-shield-check",
					open() {
						dockingStore.openPage("moderation.docker", "Moderation Docker", "mdi mdi-shield-check", ModerationPage)
					},
				},
			],
		}))
	)
}
