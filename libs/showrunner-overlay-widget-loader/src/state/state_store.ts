import type { StateAccess, Unsubscribe } from "showrunner-overlay-core"

interface StateListener {
	handler: (value: unknown) => void
}

/** Keeps one backend state subscription alive for all interested widgets. */
export class StateStore implements StateAccess {
	private readonly values = new Map<string, unknown>()
	private readonly listeners = new Map<string, Set<StateListener>>()
	private readonly explicitReferences = new Map<string, number>()

	constructor(
		private readonly onAcquire: (pluginId: string, stateId: string) => void = () => {},
		private readonly onRelease: (pluginId: string, stateId: string) => void = () => {}
	) {}

	get<T = unknown>(pluginId: string, stateId: string): T | undefined {
		return this.values.get(`${pluginId}:${stateId}`) as T | undefined
	}

	set(pluginId: string, stateId: string, value: unknown): void {
		const key = `${pluginId}:${stateId}`
		this.values.set(key, value)
		for (const listener of this.listeners.get(key) ?? []) listener.handler(value)
	}

	reconnect(): void {
		for (const key of new Set([...this.listeners.keys(), ...this.explicitReferences.keys()])) {
			const separator = key.indexOf(":")
			this.onAcquire(key.slice(0, separator), key.slice(separator + 1))
		}
	}

	acquire(pluginId: string, stateId: string): void {
		const key = `${pluginId}:${stateId}`
		const references = this.explicitReferences.get(key) ?? 0
		this.explicitReferences.set(key, references + 1)
		if (references === 0 && !this.listeners.has(key)) {
			this.values.set(key, undefined)
			this.onAcquire(pluginId, stateId)
		}
	}

	release(pluginId: string, stateId: string): void {
		const key = `${pluginId}:${stateId}`
		const references = this.explicitReferences.get(key) ?? 0
		if (references === 0) return
		if (references > 1) {
			this.explicitReferences.set(key, references - 1)
			return
		}
		this.explicitReferences.delete(key)
		if (!this.listeners.has(key)) {
			this.values.delete(key)
			this.onRelease(pluginId, stateId)
		}
	}

	watch<T = unknown>(pluginId: string, stateId: string, handler: (value: T | undefined) => void): Unsubscribe {
		const key = `${pluginId}:${stateId}`
		let listeners = this.listeners.get(key)
		if (!listeners) {
			listeners = new Set()
			this.listeners.set(key, listeners)
		}
		const listener: StateListener = { handler: handler as (value: unknown) => void }
		const wasEmpty = listeners.size === 0
		listeners.add(listener)
		if (wasEmpty && !this.explicitReferences.has(key)) this.onAcquire(pluginId, stateId)
		if (this.values.has(key)) handler(this.values.get(key) as T)
		return () => {
			if (!listeners?.delete(listener)) return
			if (listeners.size === 0) {
				this.listeners.delete(key)
				if (!this.explicitReferences.has(key)) {
					this.values.delete(key)
					this.onRelease(pluginId, stateId)
				}
			}
		}
	}

	clear(): void {
		const keys = new Set([...this.listeners.keys(), ...this.explicitReferences.keys()])
		for (const key of keys) {
			const separator = key.indexOf(":")
			this.onRelease(key.slice(0, separator), key.slice(separator + 1))
		}
		this.listeners.clear()
		this.explicitReferences.clear()
		this.values.clear()
	}
}
