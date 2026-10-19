import type { OverlayPluginContribution, OverlayWidgetDefinition } from "showrunner-overlay-core"

export interface OverlayWidgetInfo {
	pluginId: string
	definition: OverlayWidgetDefinition
}

/** Validates and indexes the generated/browser overlay widget contributions. */
export class WidgetRegistry {
	private readonly plugins = new Map<string, OverlayPluginContribution>()
	private readonly widgets = new Map<string, OverlayWidgetInfo>()

	registerPlugin(plugin: OverlayPluginContribution): void {
		if (!plugin.pluginId || !/^[a-z0-9][a-z0-9-]*$/.test(plugin.pluginId)) {
			throw new Error(`Invalid overlay plugin ID: ${plugin.pluginId}`)
		}
		if (this.plugins.has(plugin.pluginId)) throw new Error(`Duplicate overlay plugin ID: ${plugin.pluginId}`)

		const localIds = new Set<string>()
		for (const definition of plugin.widgets) {
			if (!definition.id || !/^[a-z][a-zA-Z0-9-]*$/.test(definition.id)) {
				throw new Error(`Invalid widget ID: ${plugin.pluginId}.${definition.id}`)
			}
			if (localIds.has(definition.id)) throw new Error(`Duplicate widget ID: ${plugin.pluginId}.${definition.id}`)
			localIds.add(definition.id)
			const key = `${plugin.pluginId}.${definition.id}`
			if (this.widgets.has(key)) throw new Error(`Duplicate overlay widget key: ${key}`)
			this.widgets.set(key, { pluginId: plugin.pluginId, definition })
		}

		this.plugins.set(plugin.pluginId, plugin)
	}

	registerPlugins(plugins: readonly OverlayPluginContribution[]): void {
		for (const plugin of plugins) this.registerPlugin(plugin)
	}

	get(pluginId: string, widgetId: string): OverlayWidgetInfo | undefined {
		return this.widgets.get(`${pluginId}.${widgetId}`)
	}

	getByKey(key: string): OverlayWidgetInfo | undefined {
		return this.widgets.get(key)
	}

	keys(): string[] {
		return [...this.widgets.keys()].sort()
	}

	manifest() {
		return [...this.plugins.values()]
			.sort((a, b) => a.pluginId.localeCompare(b.pluginId))
			.map((plugin) => ({
				pluginId: plugin.pluginId,
				widgets: [...plugin.widgets]
					.sort((a, b) => a.id.localeCompare(b.id))
					.map((widget) => ({
						id: widget.id,
						name: widget.name,
						description: widget.description,
						icon: widget.icon,
						defaultSize: widget.defaultSize,
						config: widget.config,
						capabilities: widget.capabilities,
					})),
			}))
	}
}
