import { PluginManager } from "showrunner-core/src/plugins/plugin-manager"
import discordPlugin from "showrunner-plugin-discord-main"
import httpPlugin from "showrunner-plugin-http-main"
import inputPlugin from "showrunner-plugin-input-main"
import iotPlugin from "showrunner-plugin-iot-main"
import minecraftPlugin from "showrunner-plugin-minecraft-main"
import obsPlugin from "showrunner-plugin-obs-main"
import osPlugin from "showrunner-plugin-os-main"
import soundPlugin from "showrunner-plugin-sound-main"
import timePlugin from "showrunner-plugin-time-main"
import twitchPlugin from "showrunner-plugin-twitch-main"
import youtubePlugin from "showrunner-plugin-youtube-main"
import voicemodPlugin from "showrunner-plugin-voicemod-main"

import variablesPlugin from "showrunner-plugin-variables-main"

import kasaPlugin from "showrunner-plugin-tplink-kasa-main"
import huePlugin from "showrunner-plugin-philips-hue-main"
import elgatoPlugin from "showrunner-plugin-elgato-main"
import lifxPlugin from "showrunner-plugin-lifx-main"
import wyzePlugin from "showrunner-plugin-wyze-main"
import goveePlugin from "showrunner-plugin-govee-main"
import twinklyPlugin from "showrunner-plugin-twinkly-main"

import spellcastPlugin from "showrunner-plugin-spellcast-main"

import streamPlanPlugin from "showrunner-plugin-stream-plans-main"

import overlayPlugin from "showrunner-plugin-overlays-main"

import dashboardPlugin from "showrunner-plugin-dashboards-main"

import randomPlugin from "showrunner-plugin-random-main"
import remotePlugin from "showrunner-plugin-remote-main"

import blueskyPlugin from "showrunner-plugin-bluesky-main"

import advssPlugin from "showrunner-plugin-advss-main"
import aitumPlugin from "showrunner-plugin-aitum-main"

import donorDrivePlugin from "showrunner-plugin-donordrive-main"
import moderationPlugin from "../../../../plugins/moderation/main/src/main"

import ShowRunnerPlugin from "./builtin-plugin"
import { WebService, Plugin } from "showrunner-core"

export async function loadPlugin(plugin: Plugin) {
	await PluginManager.getInstance().registerPlugin(plugin)
}

export async function loadPlugins() {
	const pluginManager = PluginManager.getInstance()

	await loadPlugin(ShowRunnerPlugin)
	await loadPlugin(randomPlugin)
	await loadPlugin(soundPlugin)
	await loadPlugin(overlayPlugin)
	//await loadPlugin(dashboardPlugin)

	const promises = [
		loadPlugin(timePlugin),
		loadPlugin(twitchPlugin),
		loadPlugin(youtubePlugin),
		loadPlugin(moderationPlugin),
		loadPlugin(discordPlugin),
		loadPlugin(obsPlugin),
		loadPlugin(iotPlugin),
		loadPlugin(osPlugin),
		loadPlugin(httpPlugin),
		loadPlugin(inputPlugin),
		loadPlugin(voicemodPlugin),
		loadPlugin(minecraftPlugin),
		loadPlugin(remotePlugin),
		loadPlugin(blueskyPlugin),
	]

	await Promise.allSettled(promises)

	const obsDeps = [loadPlugin(advssPlugin), loadPlugin(aitumPlugin)]
	await Promise.allSettled(obsDeps)

	await loadPlugin(variablesPlugin)

	await loadPlugin(spellcastPlugin)

	await loadPlugin(streamPlanPlugin)

	//iot
	const iotPromises = [
		loadPlugin(huePlugin),
		loadPlugin(kasaPlugin),
		loadPlugin(elgatoPlugin),
		loadPlugin(lifxPlugin),
		loadPlugin(wyzePlugin),
		loadPlugin(goveePlugin),
		loadPlugin(twinklyPlugin),
	]

	await loadPlugin(donorDrivePlugin)

	await Promise.allSettled(iotPromises)

	await WebService.getInstance().startWebsockets()
}
