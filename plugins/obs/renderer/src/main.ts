import {
	useResourceStore,
	ResourceSettingList,
	ResourceSchemaEdit,
	useDataInputStore,
	usePluginStore,
	useProjectStore,
	useDockingStore,
	ProjectGroup,
} from "castmate-ui-core"
import "./css/icons.css"
import { OBSSourceTransform } from "castmate-plugin-obs-shared"
import { computed } from "vue"

export { default as DashboardObsCard } from "./components/DashboardObsCard.vue"
export { default as ObsMainPageCard } from "./components/main-page/ObsMainPageCard.vue"

import ObsTransformInputVue from "./components/transform/ObsTransformInput.vue"

export { default as ObsPreview } from "./components/ObsPreview.vue"

import ObsConnectionEdit from "./components/connections/ObsConnectionEdit.vue"
import SceneActionComponent from "./components/action-components/SceneActionComponent.vue"
import SourceVisibilityActionComponent from "./components/action-components/SourceVisibilityActionComponent.vue"
import FilterVisibilityActionComponent from "./components/action-components/FilterVisibilityActionComponent.vue"
import PrevSceneActionComponent from "./components/action-components/PrevSceneActionComponent.vue"
import MuteSourceActionComponent from "./components/action-components/MuteSourceActionComponent.vue"
import ChangeVolumeActionComponent from "./components/action-components/ChangeVolumeActionComponent.vue"
import MediaControlsActionComponent from "./components/action-components/MediaControlsActionComponent.vue"
import ChapterMarkerActionComponent from "./components/action-components/ChapterMarkerActionComponent.vue"
import ScreenshotActionComponent from "./components/action-components/ScreenshotActionComponent.vue"
import SourceTextActionComponent from "./components/action-components/SourceTextActionComponent.vue"
import RefreshBrowserActionComponent from "./components/action-components/RefreshBrowserActionComponent.vue"
import TransformActionComponent from "./components/action-components/TransformActionComponent.vue"
import ObsIntegrationPage from "./components/ObsIntegrationPage.vue"

export function initPlugin() {
	const resourceStore = useResourceStore()

	const pluginStore = usePluginStore()
	const projectStore = useProjectStore()
	const dockingStore = useDockingStore()

	resourceStore.registerSettingComponent("OBSConnection", ResourceSettingList)
	resourceStore.registerEditComponent("OBSConnection", ObsConnectionEdit)
	resourceStore.registerCreateComponent("OBSConnection", ObsConnectionEdit)

	resourceStore.registerConfigSchema("OBSConnection", {
		type: Object,
		properties: {
			name: { type: String, name: "Connection Name", required: true, default: "OBS Connection" },
			host: { type: String, name: "Hostname", required: true, default: "127.0.0.1" },
			port: { type: Number, name: "Port", required: true, default: 4455 },
			password: { type: String, name: "Password" },
		},
	})

	projectStore.registerProjectGroupChild(
		{
			id: "integrations",
			title: "Integrations",
			icon: "mdi mdi-connection",
		},
		computed<ProjectGroup>(() => ({
			id: "obs",
			title: "OBS",
			icon: "obsi obsi-obs obs-blue",
			items: [
				{
					id: "obs.connections",
					title: "Connections",
					icon: "obsi obsi-obs obs-blue",
					open() {
						dockingStore.openPage("obs.connections", "OBS Connections", "obsi obsi-obs obs-blue", ObsIntegrationPage)
					},
				},
			],
		}))
	)

	const dataStore = useDataInputStore()

	dataStore.registerInputComponent(OBSSourceTransform, ObsTransformInputVue)

	pluginStore.setActionComponent("obs", "mute", MuteSourceActionComponent)
	pluginStore.setActionComponent("obs", "changeVolume", ChangeVolumeActionComponent)

	pluginStore.setActionComponent("obs", "mediaAction", MediaControlsActionComponent)
	pluginStore.setActionComponent("obs", "chapterMarker", ChapterMarkerActionComponent)

	pluginStore.setActionComponent("obs", "scene", SceneActionComponent)
	pluginStore.setActionComponent("obs", "prevScene", PrevSceneActionComponent)

	pluginStore.setActionComponent("obs", "source", SourceVisibilityActionComponent)
	pluginStore.setActionComponent("obs", "filter", FilterVisibilityActionComponent)
	pluginStore.setActionComponent("obs", "screenshot", ScreenshotActionComponent)
	pluginStore.setActionComponent("obs", "text", SourceTextActionComponent)
	pluginStore.setActionComponent("obs", "refreshBrowser", RefreshBrowserActionComponent)

	pluginStore.setActionComponent("obs", "transform", TransformActionComponent)
}
