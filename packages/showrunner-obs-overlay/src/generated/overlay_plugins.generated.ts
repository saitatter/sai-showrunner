// GENERATED FILE - DO NOT EDIT.

import { bindOverlayPlugin, type OverlayPluginFactories, type OverlayPluginManifest } from "showrunner-overlay-core"
import manifest from "./overlay_widgets.generated.json"

import plugin0 from "../../../../plugins/overlays/overlay/src/main.ts"
import plugin1 from "../../../../plugins/random/overlay/src/main.ts"
import plugin2 from "../../../../plugins/twitch/overlay/src/main.ts"

const pluginFactories: readonly OverlayPluginFactories[] = [plugin0, plugin1, plugin2]

export const builtInOverlayPlugins = (manifest.plugins as readonly OverlayPluginManifest[]).map((metadata) => {
	const factories = pluginFactories.find((plugin) => plugin.pluginId === metadata.pluginId)
	if (!factories) throw new Error(`Missing overlay plugin factories: ${metadata.pluginId}`)
	return bindOverlayPlugin(metadata, factories)
})
