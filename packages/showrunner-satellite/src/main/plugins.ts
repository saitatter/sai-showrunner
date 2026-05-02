import { PluginManager, Plugin } from "ShowRunner-core"

import { twitchSatellite } from "ShowRunner-plugin-twitch-main"
import { dashboardSatellite } from "ShowRunner-plugin-dashboards-main"

import { satelliteIoTPlugin } from "ShowRunner-plugin-iot-main"
import huePlugin from "ShowRunner-plugin-philips-hue-main"
import kasaPlugin from "ShowRunner-plugin-tplink-kasa-main"
import elgatoPlugin from "ShowRunner-plugin-elgato-main"
import lifxPlugin from "ShowRunner-plugin-lifx-main"
import wyzePlugin from "ShowRunner-plugin-wyze-main"
import goveePlugin from "ShowRunner-plugin-govee-main"
import twinklyPlugin from "ShowRunner-plugin-twinkly-main"

import soundPlugin from "ShowRunner-plugin-sound-main"

export async function loadPlugin(plugin: Plugin) {
	await PluginManager.getInstance().registerPlugin(plugin)
}

export async function loadPlugins() {
	await loadPlugin(twitchSatellite)
	console.log("Load Dashboard Satellite")
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
