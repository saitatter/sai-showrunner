import { describe, expect, it, vi } from "vitest"
import { LegacyOverlayProtocolAdapter, OverlayPluginContribution, OverlayWidgetDefinition, WidgetScope, mediaUrl } from "showrunner-overlay-core"
import { StateStore, ViewerDataStore, WidgetRegistry } from "./overlay-widget-loader"

const widget = (id: string): OverlayWidgetDefinition => ({
	id,
	name: id,
	defaultSize: { width: 100, height: 100 },
	config: {},
	create: () => ({ mount() {}, update() {}, destroy() {} }),
})

const plugin = (pluginId: string, widgets: OverlayWidgetDefinition[]): OverlayPluginContribution => ({ pluginId, widgets })

describe("WidgetRegistry", () => {
	it("registers and returns deterministic widget keys", () => {
		const registry = new WidgetRegistry()
		registry.registerPlugins([plugin("zeta", [widget("two")]), plugin("alpha", [widget("one")])])
		expect(registry.keys()).toEqual(["alpha.one", "zeta.two"])
		expect(registry.get("alpha", "one")?.definition.name).toBe("one")
		expect(registry.manifest().map((entry) => entry.pluginId)).toEqual(["alpha", "zeta"])
	})

	it("rejects duplicate plugin and widget IDs", () => {
		const registry = new WidgetRegistry()
		registry.registerPlugin(plugin("alpha", [widget("one")]))
		expect(() => registry.registerPlugin(plugin("alpha", []))).toThrow("Duplicate overlay plugin ID")
		expect(() => new WidgetRegistry().registerPlugin(plugin("alpha", [widget("one"), widget("one")]))).toThrow("Duplicate widget ID")
	})
})

describe("StateStore", () => {
	it("reference-counts backend subscriptions and emits cached values", () => {
		const acquired = vi.fn()
		const released = vi.fn()
		const store = new StateStore(acquired, released)
		const first = vi.fn()
		const second = vi.fn()
		const stopFirst = store.watch("obs", "scene", first)
		const stopSecond = store.watch("obs", "scene", second)
		expect(acquired).toHaveBeenCalledTimes(1)
		store.set("obs", "scene", "Main")
		expect(first).toHaveBeenCalledWith("Main")
		expect(second).toHaveBeenCalledWith("Main")
		stopFirst(); expect(released).not.toHaveBeenCalled()
		stopSecond(); expect(released).toHaveBeenCalledWith("obs", "scene")
	})

	it("keeps explicit and watched subscriptions independently alive", () => {
		const acquired = vi.fn()
		const released = vi.fn()
		const store = new StateStore(acquired, released)
		store.acquire("obs", "scene")
		const stopWatching = store.watch("obs", "scene", () => {})
		store.release("obs", "scene")
		expect(released).not.toHaveBeenCalled()
		stopWatching()
		expect(released).toHaveBeenCalledTimes(1)
	})
})

describe("ViewerDataStore", () => {
	it("uses one backend observer while multiple widgets listen", () => {
		const observed = vi.fn(); const unobserved = vi.fn()
		const store = new ViewerDataStore(observed, unobserved)
		const first = vi.fn(); const second = vi.fn()
		const stopFirst = store.observe({ onNewViewerData: first })
		const stopSecond = store.observe({ onNewViewerData: second })
		expect(observed).toHaveBeenCalledTimes(1)
		store.newRow("twitch", "viewer", { points: 3 })
		expect(first).toHaveBeenCalledWith("twitch", "viewer", { twitch: "viewer", points: 3 })
		expect(second).toHaveBeenCalledTimes(1)
		stopFirst(); stopSecond(); expect(unobserved).toHaveBeenCalledTimes(1)
	})
})

describe("LegacyOverlayProtocolAdapter", () => {
	it("classifies the legacy Dart bridge without changing its payload", () => {
		const adapter = new LegacyOverlayProtocolAdapter()
		const message = { name: "overlays_widgetRPC", requestId: "1", args: ["showAlert"] }
		expect(adapter.normalize(message)).toEqual({ ...message, kind: "command" })
		expect(adapter.normalize({ responseId: "1", result: true })).toEqual({ responseId: "1", result: true, kind: "response" })
	})
})

describe("mediaUrl", () => {
	it("resolves stored media paths through the bridge media endpoint", () => {
		expect(mediaUrl("127.0.0.1:8181", "/default/alert.mp3")).toBe("http://127.0.0.1:8181/media/default/alert.mp3")
		expect(mediaUrl("127.0.0.1:8181", "media/default/alert.mp3")).toBe("http://127.0.0.1:8181/media/default/alert.mp3")
		expect(mediaUrl("127.0.0.1:8181", "https://cdn.example.test/alert.mp3")).toBe("https://cdn.example.test/alert.mp3")
	})
})

describe("WidgetScope", () => {
	it("disposes resources once and disposes late registrations immediately", () => {
		const first = vi.fn()
		const late = vi.fn()
		const scope = new WidgetScope()
		const remove = scope.add(first)

		scope.dispose()
		scope.dispose()
		expect(first).toHaveBeenCalledTimes(1)

		scope.add(late)
		expect(late).toHaveBeenCalledTimes(1)
		remove()
		expect(first).toHaveBeenCalledTimes(1)
	})
})
