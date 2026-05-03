import { OverlayPluginOptions, OverlayWidgetComponent } from "showrunner-overlay-core"
import overlaysPlugin from "showrunner-plugin-overlays-overlays"
import randomPlugin from "showrunner-plugin-random-overlays"
import twitchPlugin from "showrunner-plugin-twitch-overlays"
import { defineStore } from "pinia"
import { ref, Component, computed, markRaw } from "vue"

export interface OverlayWidgetInfo {
	plugin: string
	component: OverlayWidgetComponent
}

export const useOverlayWidgets = defineStore("ShowRunner-overlay-widgets", () => {
	const widgets = ref(new Map<string, OverlayWidgetInfo>())

	function loadPluginWidgets(opts: OverlayPluginOptions) {
		for (const widget of opts.widgets) {
			widgets.value.set(`${opts.id}.${widget.widget.id}`, { plugin: opts.id, component: markRaw(widget) })
		}
	}

	function getWidget(plugin: string, widget: string) {
		return widgets.value.get(`${plugin}.${widget}`)
	}

	return { loadPluginWidgets, getWidget, widgets: computed<OverlayWidgetInfo[]>(() => [...widgets.value.values()]) }
})

export function loadOverlayWidgets() {
	const widgets = useOverlayWidgets()

	widgets.loadPluginWidgets(overlaysPlugin)
	widgets.loadPluginWidgets(randomPlugin)
	widgets.loadPluginWidgets(twitchPlugin)
}
