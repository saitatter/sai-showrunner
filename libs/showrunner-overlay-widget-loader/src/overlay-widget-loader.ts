import {
	OverlayConfig,
	OverlayPluginContribution,
	OverlayTransport,
	OverlayTransportMessage,
	OverlayWidgetConfig,
	OverlayWidgetDefinition,
	StateAccess,
	Unsubscribe,
	ViewerDataAccess,
	ViewerDataObserver,
	ViewerDataRow,
	ViewerVariable,
	WidgetBridge,
	WidgetContext,
	OverlayWidget,
	LegacyOverlayProtocolAdapter,
	mediaUrl,
	playMedia,
} from "showrunner-overlay-core"

export interface OverlayWidgetInfo {
	pluginId: string
	definition: OverlayWidgetDefinition
}

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

interface StateListener {
	handler: (value: unknown) => void
}

interface EventHandler {
	widgetId: string
	handler: (event: unknown) => void
}

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

export class ViewerDataStore implements ViewerDataAccess {
	private readonly observers = new Set<ViewerDataObserver>()

	constructor(
		private readonly onObserve: () => void = () => {},
		private readonly onUnobserve: () => void = () => {},
		private readonly onQuery: ViewerDataAccess["query"] = async () => [],
		private readonly onGetVariables: ViewerDataAccess["getVariables"] = async () => []
	) {}

	observe(observer: ViewerDataObserver): Unsubscribe {
		if (this.observers.has(observer)) return () => this.observers.delete(observer)
		const wasEmpty = this.observers.size === 0
		this.observers.add(observer)
		if (wasEmpty) this.onObserve()
		return () => {
			if (!this.observers.delete(observer)) return
			if (this.observers.size === 0) this.onUnobserve()
		}
	}

	query(start: number, end: number, sortBy?: string, sortOrder?: number): Promise<ViewerDataRow[]> {
		return this.onQuery(start, end, sortBy, sortOrder)
	}

	getVariables(): Promise<ViewerVariable[]> {
		return this.onGetVariables()
	}

	newRow(provider: string, id: string, row: ViewerDataRow): void {
		for (const observer of this.observers) observer.onNewViewerData?.(provider, id, { [provider]: id, ...row })
	}

	reconnect(): void {
		if (this.observers.size > 0) this.onObserve()
	}

	changed(provider: string, id: string, variable: string, value: unknown): void {
		for (const observer of this.observers) observer.onViewerDataChanged?.(provider, id, variable, value)
	}

	removed(provider: string, id: string): void {
		for (const observer of this.observers) observer.onViewerDataRemoved?.(provider, id)
	}

	newVariable(variable: ViewerVariable): void {
		for (const observer of this.observers) observer.onNewViewerVariable?.(variable)
	}

	deleteVariable(name: string): void {
		for (const observer of this.observers) observer.onViewerVariableDeleted?.(name)
	}
}

export interface OverlayRuntimeOptions {
	root: HTMLElement
	transport: OverlayTransport
	registry: WidgetRegistry
	overlayId: string
	isEditor?: boolean
	statusVisible?: boolean
	host?: string
}

interface WidgetInstance {
	config: OverlayWidgetConfig
	container: HTMLElement
	widget: OverlayWidget
	cleanups: Unsubscribe[]
}

export class OverlayRuntime {
	private static readonly supportedSchemaVersion = 1
	private readonly instances = new Map<string, WidgetInstance>()
	private readonly eventHandlers = new Map<string, Set<EventHandler>>()
	private readonly commandHandlers = new Map<string, (args: unknown) => unknown | Promise<unknown>>()
	private readonly pending = new Map<string, { resolve: (value: unknown) => void; reject: (reason: unknown) => void }>()
	private readonly playingAudio = new Map<string, HTMLAudioElement>()
	private readonly protocol = new LegacyOverlayProtocolAdapter()
	private readonly stateStore: StateStore
	private readonly viewerData: ViewerDataStore
	private config: OverlayConfig = { name: "UNLOADED OVERLAY", size: { width: 0, height: 0 }, widgets: [] }
	private unsubscribeTransport?: Unsubscribe
	private unsubscribeTransportStatus?: Unsubscribe
	private nextRequest = 0
	private hasConnected = false
	private readonly status?: HTMLElement

	constructor(private readonly options: OverlayRuntimeOptions) {
		this.stateStore = new StateStore(
			(pluginId, stateId) => void this.callBackend("overlays_acquireState", pluginId, stateId),
			(pluginId, stateId) => void this.callBackend("overlays_freeState", pluginId, stateId)
		)
		this.viewerData = new ViewerDataStore(
			() => void this.callBackend("overlays_observeViewerData"),
			() => void this.callBackend("overlays_unobserveViewerData"),
			(start, end, sortBy, sortOrder) => this.callBackend<ViewerDataRow[]>("overlays_queryViewerData", start, end, sortBy, sortOrder),
			() => this.callBackend<ViewerVariable[]>("overlays_getViewerVariables")
		)
		if (options.statusVisible) {
			this.status = document.createElement("div")
			this.status.className = "overlay-status overlay-status--idle"
			options.root.appendChild(this.status)
		}
	}

	async start(): Promise<void> {
		if (this.unsubscribeTransport) return
		this.unsubscribeTransport = this.options.transport.onMessage((message) => void this.handleMessage(message))
		this.unsubscribeTransportStatus = this.options.transport.onStatus?.((status) => {
			this.setStatus(status)
			if (status !== "connected") return
			if (this.hasConnected) {
				this.stateStore.reconnect()
				this.viewerData.reconnect()
			}
			this.hasConnected = true
		})
		this.setStatus("connecting")
		await this.options.transport.connect()
		this.hasConnected = true
		this.setStatus("connected")
	}

	async stop(): Promise<void> {
		this.unsubscribeTransport?.()
		this.unsubscribeTransport = undefined
		this.unsubscribeTransportStatus?.()
		this.unsubscribeTransportStatus = undefined
		this.hasConnected = false
		for (const id of [...this.instances.keys()]) this.removeInstance(id)
		this.stateStore.clear()
		for (const audio of this.playingAudio.values()) audio.pause()
		this.playingAudio.clear()
		for (const pending of this.pending.values()) pending.reject(new Error("Overlay runtime stopped."))
		this.pending.clear()
		await this.options.transport.close()
		this.setStatus("idle")
	}

	getConfig(): OverlayConfig {
		return this.config
	}

	private setStatus(status: string): void {
		if (!this.status) return
		this.status.className = `overlay-status overlay-status--${status}`
		this.status.textContent = status.charAt(0).toUpperCase() + status.slice(1)
	}

	private async handleMessage(message: OverlayTransportMessage): Promise<void> {
		message = this.protocol.normalize(message)
		if (message.responseId) {
			const call = this.pending.get(message.responseId)
			if (!call) return
			this.pending.delete(message.responseId)
			if (message.failed) call.reject(message.failed)
			else call.resolve(message.result)
			return
		}
		if (!message.name || !message.requestId) return
		try {
			const result = await this.handleRequest(message.name, message.args ?? [])
			this.options.transport.send({ responseId: message.requestId, result })
		} catch (error) {
			this.options.transport.send({ responseId: message.requestId, failed: String(error) })
		}
	}

	private async handleRequest(name: string, args: unknown[]): Promise<unknown> {
		switch (name) {
			case "overlays_setConfig":
				this.setConfig(args[0] as OverlayConfig)
				return undefined
			case "overlays_stateUpdate":
				this.stateStore.set(String(args[0]), String(args[1]), args[2])
				return undefined
			case "overlays_widget":
				this.emitMessage(String(args[0]), args[1])
				return undefined
			case "overlays_widgetRPC":
				return this.commandHandlers.get(`${String(args[0])}.${String(args[1])}`)?.(args.slice(2))
			case "overlays_broadcast":
				this.emitMessage(String(args[0]), args.length === 2 ? args[1] : args.slice(1))
				return undefined
			case "overlays_onNewViewerData":
				this.viewerData.newRow(String(args[0]), String(args[1]), args[2] as ViewerDataRow)
				return undefined
			case "overlays_onViewerDataChanged":
				this.viewerData.changed(String(args[0]), String(args[1]), String(args[2]), args[3])
				return undefined
			case "overlays_onViewerDataRemoved":
				this.viewerData.removed(String(args[0]), String(args[1]))
				return undefined
			case "overlays_onNewViewerVariable":
				this.viewerData.newVariable({ name: String(args[0]), schema: args[1] })
				return undefined
			case "overlays_onViewerVariableDeleted":
				this.viewerData.deleteVariable(String(args[0]))
				return undefined
			case "overlays_playAudio":
				{
					const playId = String(args[1] ?? "")
					const audio = playMedia(this.options.host ?? window.location.host, String(args[0]), {
						playId,
						startSec: Number(args[2]),
						endSec: args[3] == null ? undefined : Number(args[3]),
						volume: args[4] == null ? undefined : Number(args[4]),
					})
					if (audio && playId) {
						this.playingAudio.get(playId)?.pause()
						this.playingAudio.set(playId, audio)
						const clear = () => { if (this.playingAudio.get(playId) === audio) this.playingAudio.delete(playId) }
						audio.addEventListener("ended", clear, { once: true })
						audio.addEventListener("pause", clear, { once: true })
					}
				}
				return undefined
			case "overlays_cancelAudio":
				{
					const playId = String(args[0] ?? "")
					this.playingAudio.get(playId)?.pause()
					this.playingAudio.delete(playId)
				}
				return undefined
			default:
				return undefined
		}
	}

	private setConfig(config: OverlayConfig): void {
		if (!config || typeof config !== "object" || !config.size || !Array.isArray(config.widgets)) {
			this.setStatus("invalid-config")
			console.error("Invalid overlay definition received.")
			return
		}
		if (config.schemaVersion !== undefined && config.schemaVersion > OverlayRuntime.supportedSchemaVersion) {
			this.setStatus("unsupported-config")
			console.error(`Unsupported overlay schema version: ${config.schemaVersion}`)
			return
		}
		this.config = config
		document.title = `ShowRunner Overlay -- ${config.name}`
		const desired = new Set(config.widgets.filter((widget) => widget.visible).map((widget) => widget.id))
		for (const id of [...this.instances.keys()]) if (!desired.has(id)) this.removeInstance(id)
		for (const widgetConfig of config.widgets) {
			if (!widgetConfig.visible) continue
			const existing = this.instances.get(widgetConfig.id)
			if (existing) {
				existing.config = widgetConfig
				existing.widget.update(widgetConfig.config)
				this.position(existing.container, widgetConfig)
				continue
			}
			this.addInstance(widgetConfig)
		}
	}

	private addInstance(config: OverlayWidgetConfig): void {
		const info = this.options.registry.get(config.plugin, config.widget)
		if (!info) {
			console.error(`Unknown overlay widget ${config.plugin}.${config.widget}`)
			return
		}
		const container = document.createElement("div")
		container.className = "overlay-widget"
		container.dataset.widgetId = config.id
		this.position(container, config)
		this.options.root.appendChild(container)
		const bridge = this.createBridge(config)
		const context: WidgetContext = {
			overlayId: this.options.overlayId,
			widgetId: config.id,
			bridge,
			state: this.stateStore,
			viewerData: this.viewerData,
			isEditor: this.options.isEditor ?? false,
			mediaUrl: (file) => mediaUrl(this.options.host ?? window.location.host, file),
		}
		const widget = info.definition.create(context, config.config)
		this.instances.set(config.id, { config, container, widget, cleanups: [] })
		widget.mount(container, config.config, context)
	}

	private removeInstance(id: string): void {
		const instance = this.instances.get(id)
		if (!instance) return
		for (const cleanup of instance.cleanups) cleanup()
		instance.widget.destroy()
		instance.container.remove()
		this.instances.delete(id)
	}

	private position(container: HTMLElement, config: OverlayWidgetConfig): void {
		container.style.cssText = `position:absolute;left:${config.position.x}px;top:${config.position.y}px;width:${config.size.width}px;height:${config.size.height}px;`
		container.style.display = config.visible ? "block" : "none"
	}

	private createBridge(config: OverlayWidgetConfig): WidgetBridge {
		return {
			overlayId: this.options.overlayId,
			widgetId: config.id,
			getConfig: () => this.instances.get(config.id)?.config ?? config,
			onEvent: (type, handler) => {
				const key = String(type)
				let handlers = this.eventHandlers.get(key)
				if (!handlers) {
					handlers = new Set()
					this.eventHandlers.set(key, handlers)
				}
				const entry = { widgetId: config.id, handler: handler as (event: unknown) => void }
				handlers.add(entry)
				return () => {
					handlers?.delete(entry)
					if (handlers?.size === 0) this.eventHandlers.delete(key)
				}
			},
			exposeCommand: (command, handler) => {
				const key = `${config.id}.${String(command)}`
				this.commandHandlers.set(key, handler as (args: unknown) => unknown | Promise<unknown>)
				return () => this.commandHandlers.delete(key)
			},
			watchState: (pluginId, stateId, handler) => this.stateStore.watch(pluginId, stateId, handler),
			getState: (pluginId, stateId) => this.stateStore.get(pluginId, stateId),
			acquireState: (pluginId, stateId) => this.stateStore.acquire(pluginId, stateId),
			releaseState: (pluginId, stateId) => this.stateStore.release(pluginId, stateId),
			callRPC: (id, ...args) => this.callBackend("overlays_widgetRPC", id, config.id, ...args),
			observeViewerData: (observer) => this.viewerData.observe(observer),
			queryViewerData: (start, end, sortBy, sortOrder) => this.viewerData.query(start, end, sortBy, sortOrder),
			getViewerVariables: () => this.viewerData.getVariables(),
			playSound: (file) => playMedia(this.options.host ?? window.location.host, file),
		}
	}

	private emitMessage(id: string, payload: unknown): void {
		const target = payload && typeof payload === "object" && !Array.isArray(payload)
			? (payload as Record<string, unknown>).targetWidgetId?.toString()
			: undefined
		for (const entry of this.eventHandlers.get(id) ?? []) {
			if (target && target !== entry.widgetId) continue
			try {
				entry.handler(payload)
			} catch (error) {
				console.error(`Overlay event handler failed: ${id}`, error)
			}
		}
	}

	private callBackend<T = unknown>(name: string, ...args: unknown[]): Promise<T> {
		const requestId = `overlay-${Date.now()}-${this.nextRequest++}`
		return new Promise<T>((resolve, reject) => {
			this.pending.set(requestId, { resolve: resolve as (value: unknown) => void, reject })
			this.options.transport.send({ requestId, name, args })
		})
	}
}
