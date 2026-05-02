import { OverlayPluginOptions, OverlayWidgetComponent } from "ShowRunner-overlay-core"
import overlaysPlugin from "ShowRunner-plugin-overlays-overlays"
import randomPlugin from "ShowRunner-plugin-random-overlays"
import twitchPlugin from "ShowRunner-plugin-twitch-overlays"
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

			console.log("Loading Overlay Widget", opts.id, widget.widget.id, widget.widget.name)
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
