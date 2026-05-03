import {
	initializeProfiles,
	initializeAutomations,
	useDocumentStore,
	usePluginStore,
	useProjectStore,
	useResourceStore,
	useMediaStore,
	useActionQueueStore,
	useIpcCaller,
	initializeStreamPlans,
	useStreamPlanStore,
	useInitStore,
	useSatelliteConnection,
	useSatelliteMedia,
} from "ShowRunner-ui-core"
import { createApp } from "vue"
import App from "./App.vue"

import PrimeVue from "primevue/config"
import { i18n } from "./i18n"
import DialogService from "primevue/dialogservice"
import ConfirmationService from "primevue/confirmationservice"

//theme
// import "primevue/resources/themes/lara-dark-blue/theme.css"
//import "./theme/ShowRunner/theme.scss"
import "./css/theme-ext.css"
import "./css/spellcast.css"
//core
//import "primevue/resources/primevue.min.css"
import Aura from "@primevue/themes/aura"

import "primeicons/primeicons.css"
import "primeflex/primeflex.css"

import "@mdi/font/css/materialdesignicons.css"

import { createPinia } from "pinia"
import ProfileEditorVue from "./components/profiles/ProfileEditor.vue"
import AutomationEditPageVue from "./components/automation/AutomationEditPage.vue"
import { initData, StreamPlanEditorPage, useSatelliteResourceStore } from "ShowRunner-ui-core"

import { initPlugin as initSoundPlugin } from "ShowRunner-plugin-sound-renderer"
import { initPlugin as initVariablesPlugin } from "ShowRunner-plugin-variables-renderer"
import { initPlugin as initTwitchPlugin } from "ShowRunner-plugin-twitch-renderer"
import { initPlugin as initYouTubePlugin } from "ShowRunner-plugin-youtube-renderer"
import { initPlugin as initObsPlugin } from "ShowRunner-plugin-obs-renderer"
import { initPlugin as initDiscordPlugin } from "ShowRunner-plugin-discord-renderer"
import { initPlugin as initInputPlugin } from "ShowRunner-plugin-input-renderer"
import { initPlugin as initTimePlugin } from "ShowRunner-plugin-time-renderer"
import { initPlugin as initMinecraftPlugin } from "ShowRunner-plugin-minecraft-renderer"
import { initPlugin as initIoTPlugin } from "ShowRunner-plugin-iot-renderer"
import { initPlugin as initTwinklyPlugin } from "ShowRunner-plugin-twinkly-renderer"
import { initPlugin as initHuePlugin } from "ShowRunner-plugin-philips-hue-renderer"
import { initPlugin as initWyzePlugin } from "ShowRunner-plugin-wyze-renderer"
import { initPlugin as initLifxPlugin } from "ShowRunner-plugin-lifx-renderer"
import { initPlugin as initGoveePlugin } from "ShowRunner-plugin-govee-renderer"
import { initPlugin as initKasaPlugin } from "ShowRunner-plugin-tplink-kasa-renderer"
import { initPlugin as initOsPlugin } from "ShowRunner-plugin-os-renderer"
import { initPlugin as initOverlaysPlugin } from "ShowRunner-plugin-overlays-renderer"
import { initPlugin as initSpellCastPlugin } from "ShowRunner-plugin-spellcast-renderer"

import { initPlugin as initDashboardPlugin } from "ShowRunner-plugin-dashboards-renderer"

import { initPlugin as initRandomPlugin } from "ShowRunner-plugin-random-renderer"

import { initPlugin as initRemotePlugin } from "ShowRunner-plugin-remote-renderer"

import { initPlugin as initBlueSkyPlugin } from "ShowRunner-plugin-bluesky-renderer"

import { initPlugin as initAdvssPlugin } from "ShowRunner-plugin-advss-renderer"
import { initPlugin as initAitumPlugin } from "ShowRunner-plugin-aitum-renderer"
import { initPlugin as initModerationPlugin } from "../../../../plugins/moderation/renderer/src/main"

import { loadOverlayWidgets } from "ShowRunner-overlay-widget-loader"
import { loadDashboardWidgets } from "ShowRunner-dashboard-widget-loader"

import { useMainPageStore } from "./util/main-page"
import { initializeQueues } from "./util/queues"
import { initSettingsDocuments } from "./components/settings/SettingsTypes"
import Tooltip from "primevue/tooltip"
import ToastService from "primevue/toastservice"
import { IPCOverlayWidgetDescriptor } from "ShowRunner-plugin-overlays-shared"
import { sendDashboardsToMain, sendOverlaysToMain } from "./util/overlay-util"
import { setupProxyDialogService } from "../../../../libs/ShowRunner-ui-core/src/util/dialog-helper"
import { definePreset } from "@primevue/themes"
import KeyFilter from "primevue/keyfilter"
/*
const router = createRouter({
	history: createWebHistory(),
	routes: [],
})*/

const pinia = createPinia()
const app = createApp(App)

const ShowRunnerPreset = definePreset(Aura, {
	semantic: {
		primary: {
			50: "#fefbff",
			100: "#faebff",
			200: "#f6daff",
			300: "#f1caff",
			400: "#edbaff",
			500: "#e9aaff",
			600: "#c691d9",
			700: "#a377b3",
			800: "#805e8c",
			900: "#5d4466",
			950: "#3a2b40",
		},
		colorScheme: {
			dark: {
				surface: {
					0: "#ffffff",
					50: "#f8f8f8",
					100: "#dcdddd",
					200: "#c1c2c3",
					300: "#a5a7a8",
					400: "#8a8c8e",
					500: "#6e7173",
					600: "#5e6062",
					700: "#4d4f51",
					800: "#3c3c3c",
					900: "#212121",
					950: "#121212",
				},
			},
		},
	},
})

//DialogService.install?.(app)
app.use(PrimeVue, {
	theme: {
		preset: ShowRunnerPreset,
		options: {
			darkModeSelector: ".ShowRunner-dark-mode",
		},
	},
})
//app.use(DialogService)
setupProxyDialogService(app)

app.use(ConfirmationService)
app.use(ToastService)

app.directive("keyfilter", KeyFilter)
app.directive("tooltip", Tooltip)
//app.use(Maska)

//app.use(router)
app.use(pinia)
app.use(i18n)

const initStore = useInitStore()
const pluginStore = usePluginStore()
const projecStore = useProjectStore()
const documentStore = useDocumentStore()
const resourceStore = useResourceStore()
const actionQueueStore = useActionQueueStore()
const mainPageStore = useMainPageStore()
const mediaStore = useMediaStore()
const planStore = useStreamPlanStore()

const satelliteStore = useSatelliteConnection()
const satelliteResources = useSatelliteResourceStore()
const satelliteMedia = useSatelliteMedia()

const uiLoadComplete = useIpcCaller("plugins", "uiLoadComplete")

async function init() {
	//Wait for the main process to initialize
	await initStore.initialize("ShowRunner")

	await initStore.waitForInitialSetup()

	//Now init all the stores
	await initData()
	await pluginStore.initialize()
	await resourceStore.initialize()
	await projecStore.initialize()

	await initStore.waitForInit()

	await actionQueueStore.initialize()
	await mainPageStore.initialize()
	await planStore.initialize()

	await initializeProfiles(app)
	await initializeAutomations(app)
	await initializeStreamPlans(app)

	documentStore.registerDocumentComponent("profile", ProfileEditorVue)
	documentStore.registerDocumentComponent("automation", AutomationEditPageVue)
	documentStore.registerDocumentComponent("streamplan", StreamPlanEditorPage)

	initSettingsDocuments()

	initializeQueues()

	await initOverlaysPlugin(app)

	//await initDashboardPlugin(app)

	await initVariablesPlugin()
	await initTwitchPlugin(app)
	await initYouTubePlugin(app)
	await initModerationPlugin(app)
	await initSpellCastPlugin(app)

	//TODO: This init function is bonkers, we should formalize initing these plugins after their main process side gets inited.

	await initSoundPlugin(app)
	await initTimePlugin()
	await initObsPlugin()
	await initDiscordPlugin()
	await initInputPlugin()
	await initOsPlugin()
	await initIoTPlugin()
	await initMinecraftPlugin()
	await initTwinklyPlugin()
	await initHuePlugin()
	await initWyzePlugin()
	await initLifxPlugin()
	await initGoveePlugin()
	await initKasaPlugin()
	await initRemotePlugin()
	await initBlueSkyPlugin()

	await initAdvssPlugin()
	await initAitumPlugin()
	await initRandomPlugin()

	await mediaStore.initialize()

	await satelliteStore.initialize()
	await satelliteResources.initialize()
	await satelliteMedia.initialize()

	loadOverlayWidgets()
	loadDashboardWidgets()

	sendOverlaysToMain()
	//sendDashboardsToMain()

	await uiLoadComplete()

	mainPageStore.openMain()
}

init()

//TODO: Better Plugin Initialization

app.mount("#app")
