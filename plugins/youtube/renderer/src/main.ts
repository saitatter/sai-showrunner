import { App, computed } from "vue"
import { ProjectGroup, useDockingStore, useProjectStore } from "castmate-ui-core"
import YouTubePage from "./components/YouTubePage.vue"

export async function initPlugin(app: App<Element>) {
	const projectStore = useProjectStore()
	const dockingStore = useDockingStore()

	projectStore.registerProjectGroupItem(
		computed<ProjectGroup>(() => ({
			id: "youtube",
			title: "YouTube",
			icon: "mdi mdi-youtube",
			items: [
				{
					id: "youtube.live",
					title: "Live Integration",
					icon: "mdi mdi-broadcast",
					open() {
						dockingStore.openPage("youtube.live", "YouTube", "mdi mdi-youtube", YouTubePage)
					},
				},
			],
		}))
	)
}
