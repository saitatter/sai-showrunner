import { PluginManager } from "ShowRunner-core/src/plugins/plugin-manager"
import discordPlugin from "ShowRunner-plugin-discord-main"
import httpPlugin from "ShowRunner-plugin-http-main"
import inputPlugin from "ShowRunner-plugin-input-main"
import iotPlugin from "ShowRunner-plugin-iot-main"
import minecraftPlugin from "ShowRunner-plugin-minecraft-main"
import obsPlugin from "ShowRunner-plugin-obs-main"
import osPlugin from "ShowRunner-plugin-os-main"
import soundPlugin from "ShowRunner-plugin-sound-main"
import timePlugin from "ShowRunner-plugin-time-main"
import twitchPlugin from "ShowRunner-plugin-twitch-main"
import youtubePlugin from "ShowRunner-plugin-youtube-main"
import voicemodPlugin from "ShowRunner-plugin-voicemod-main"

import variablesPlugin from "ShowRunner-plugin-variables-main"

import kasaPlugin from "ShowRunner-plugin-tplink-kasa-main"
import huePlugin from "ShowRunner-plugin-philips-hue-main"
import elgatoPlugin from "ShowRunner-plugin-elgato-main"
import lifxPlugin from "ShowRunner-plugin-lifx-main"
import wyzePlugin from "ShowRunner-plugin-wyze-main"
import goveePlugin from "ShowRunner-plugin-govee-main"
import twinklyPlugin from "ShowRunner-plugin-twinkly-main"

import spellcastPlugin from "ShowRunner-plugin-spellcast-main"

import streamPlanPlugin from "ShowRunner-plugin-stream-plans-main"

import overlayPlugin from "ShowRunner-plugin-overlays-main"

import dashboardPlugin from "ShowRunner-plugin-dashboards-main"

import randomPlugin from "ShowRunner-plugin-random-main"
import remotePlugin from "ShowRunner-plugin-remote-main"

import blueskyPlugin from "ShowRunner-plugin-bluesky-main"

import advssPlugin from "ShowRunner-plugin-advss-main"
import aitumPlugin from "ShowRunner-plugin-aitum-main"

import donorDrivePlugin from "ShowRunner-plugin-donordrive-main"
import moderationPlugin from "../../../../plugins/moderation/main/src/main"

import ShowRunnerPlugin from "./builtin-plugin"
import { WebService, Plugin } from "ShowRunner-core"
import { migratePlugin } from "./migration/old-migration"

export async function loadPlugin(plugin: Plugin) {
	await migratePlugin(plugin.id)
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
