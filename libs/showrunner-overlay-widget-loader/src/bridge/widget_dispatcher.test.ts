import { describe, expect, it, vi } from "vitest"
import { WidgetScope } from "showrunner-overlay-core"
import { WidgetCommandRegistry, WidgetEventRegistry } from "./widget_dispatcher"

describe("WidgetEventRegistry", () => {
	it("routes events and respects a target widget", () => {
		const registry = new WidgetEventRegistry()
		const first = new WidgetScope()
		const second = new WidgetScope()
		const received: string[] = []
		registry.register("message", "first", (payload) => received.push(`first:${String(payload)}`), first)
		registry.register("message", "second", (payload) => received.push(`second:${String(payload)}`), second)

		registry.emit("message", { targetWidgetId: "second" })

		expect(received).toEqual(["second:[object Object]"])
		first.dispose()
		second.dispose()
	})

	it("removes handlers when their widget scope is disposed", () => {
		const registry = new WidgetEventRegistry()
		const scope = new WidgetScope()
		const handler = vi.fn()
		registry.register("message", "widget", handler, scope)
		scope.dispose()

		registry.emit("message", "payload")

		expect(handler).not.toHaveBeenCalled()
	})
})

describe("WidgetCommandRegistry", () => {
	it("invokes commands and cleans them up with the widget scope", async () => {
		const registry = new WidgetCommandRegistry()
		const scope = new WidgetScope()
		registry.register("widget.show", async (args) => `ok:${String(args)}`, scope)

		expect(await registry.invoke("widget.show", ["alert"])).toBe("ok:alert")
		scope.dispose()
		expect(registry.invoke("widget.show", ["alert"])).toBeUndefined()
	})

	it("does not let stale cleanup delete a replacement command", () => {
		const registry = new WidgetCommandRegistry()
		const oldScope = new WidgetScope()
		const newScope = new WidgetScope()
		registry.register("widget.show", () => "old", oldScope)
		registry.register("widget.show", () => "new", newScope)
		oldScope.dispose()

		expect(registry.invoke("widget.show", [])).toBe("new")
		newScope.dispose()
	})
})
