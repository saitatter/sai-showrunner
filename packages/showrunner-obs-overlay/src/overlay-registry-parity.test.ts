import { describe, expect, it } from "vitest"
import manifest from "./generated/overlay_widgets.generated.json"
import { builtInOverlayPlugins } from "./generated/overlay_plugins.generated"
import { WidgetRegistry } from "showrunner-overlay-widget-loader"

describe("generated overlay registry parity", () => {
	it("keeps the browser registry and language-neutral catalog on the same keys", () => {
		const registry = new WidgetRegistry()
		registry.registerPlugins(builtInOverlayPlugins)
		const manifestKeys = manifest.plugins.flatMap((plugin) => plugin.widgets.map((widget) => `${plugin.pluginId}.${widget.id}`)).sort()

		expect(registry.keys()).toEqual(manifestKeys)
		const runtimeWidgets = registry.manifest().flatMap((plugin) => plugin.widgets.map((widget) => ({ pluginId: plugin.pluginId, ...widget })))
		const generatedWidgets = manifest.plugins.flatMap((plugin) => plugin.widgets.map((widget) => ({ pluginId: plugin.pluginId, ...widget })))
		for (const generated of generatedWidgets) {
			const runtime = runtimeWidgets.find((widget) => widget.pluginId === generated.pluginId && widget.id === generated.id)
			expect(runtime).toMatchObject({
				pluginId: generated.pluginId,
				id: generated.id,
				name: generated.name,
				description: generated.description,
				icon: generated.icon,
				defaultSize: generated.defaultSize,
				capabilities: generated.capabilities,
			})
		}
	})

	it("keeps generated config metadata available for Flutter", () => {
		const shader = manifest.plugins.find((plugin) => plugin.pluginId === "overlays")?.widgets.find((widget) => widget.id === "shaderLayer")
		expect(shader?.config?.preset?.default).toBe("aurora")
		expect(shader?.config?.shaderGraph?.type).toBe("object")
	})
})
