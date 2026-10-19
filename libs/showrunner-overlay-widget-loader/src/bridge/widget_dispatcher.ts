import { Unsubscribe, WidgetScope } from "showrunner-overlay-core"

interface EventHandler {
	widgetId: string
	handler: (event: unknown) => void
}

type CommandHandler = (args: unknown) => unknown | Promise<unknown>

/** Owns event subscriptions for mounted widgets and their scoped cleanup. */
export class WidgetEventRegistry {
	private readonly handlers = new Map<string, Set<EventHandler>>()

	register(type: string, widgetId: string, handler: (event: unknown) => void, scope: WidgetScope): Unsubscribe {
		let handlers = this.handlers.get(type)
		if (!handlers) {
			handlers = new Set<EventHandler>()
			this.handlers.set(type, handlers)
		}
		const entry = { widgetId, handler }
		handlers.add(entry)
		return scope.add(() => {
			handlers?.delete(entry)
			if (handlers?.size === 0) this.handlers.delete(type)
		})
	}

	emit(type: string, payload: unknown): void {
		const target =
			payload && typeof payload === "object" && !Array.isArray(payload)
				? (payload as Record<string, unknown>).targetWidgetId?.toString()
				: undefined
		for (const entry of this.handlers.get(type) ?? []) {
			if (target && target !== entry.widgetId) continue
			try {
				entry.handler(payload)
			} catch (error) {
				console.error(`Overlay event handler failed: ${type}`, error)
			}
		}
	}
}

/** Owns widget RPC commands and prevents stale cleanup from deleting a replacement. */
export class WidgetCommandRegistry {
	private readonly handlers = new Map<string, CommandHandler>()

	register(key: string, handler: CommandHandler, scope: WidgetScope): Unsubscribe {
		this.handlers.set(key, handler)
		return scope.add(() => {
			if (this.handlers.get(key) === handler) this.handlers.delete(key)
		})
	}

	invoke(key: string, args: unknown[]): unknown | Promise<unknown> {
		return this.handlers.get(key)?.(args)
	}
}
