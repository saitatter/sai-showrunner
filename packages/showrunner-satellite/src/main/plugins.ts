import { PluginManager, Plugin } from "showrunner-core"

import { twitchSatellite } from "showrunner-plugin-twitch-main"
import { dashboardSatellite } from "showrunner-plugin-dashboards-main"

import { satelliteIoTPlugin } from "showrunner-plugin-iot-main"
import huePlugin from "showrunner-plugin-philips-hue-main"
import kasaPlugin from "showrunner-plugin-tplink-kasa-main"
import elgatoPlugin from "showrunner-plugin-elgato-main"
import lifxPlugin from "showrunner-plugin-lifx-main"
import wyzePlugin from "showrunner-plugin-wyze-main"
import goveePlugin from "showrunner-plugin-govee-main"
import twinklyPlugin from "showrunner-plugin-twinkly-main"

import soundPlugin from "showrunner-plugin-sound-main"

export async function loadPlugin(plugin: Plugin) {
	await PluginManager.getInstance().registerPlugin(plugin)
}

export async function loadPlugins() {
	await loadPlugin(twitchSatellite)
	await loadPlugin(dashboardSatellite)

	await loadPlugin(satelliteIoTPlugin)

	await loadPlugin(soundPlugin)
	//iot
	const iotPromises: Promise<any>[] = [
		loadPlugin(huePlugin),
		loadPlugin(kasaPlugin),
		loadPlugin(elgatoPlugin),
		loadPlugin(lifxPlugin),
		loadPlugin(wyzePlugin),
		loadPlugin(goveePlugin),
		loadPlugin(twinklyPlugin),
	]

	await Promise.allSettled(iotPromises)

	//await WebService.getInstance().startWebsockets()
}
