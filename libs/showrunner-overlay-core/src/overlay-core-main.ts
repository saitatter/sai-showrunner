export type CSSProperties = Record<string, string | number | undefined>

export type Unsubscribe = () => void

/** Owns every disposable resource created by one mounted overlay widget. */
export class WidgetScope {
	private readonly disposables = new Set<Unsubscribe>()
	private disposed = false

	add(dispose: Unsubscribe): Unsubscribe {
		if (this.disposed) {
			dispose()
			return () => {}
		}

		let active = true
		const remove = () => {
			if (!active) return
			active = false
			this.disposables.delete(remove)
			dispose()
		}
		this.disposables.add(remove)
		return remove
	}

	/** Schedules work that is cancelled automatically with the widget. */
	timeout(callback: () => void, delayMs: number): number {
		const handle = window.setTimeout(callback, Math.max(0, delayMs))
		this.add(() => window.clearTimeout(handle))
		return handle
	}

	/** Schedules repeating work that is cancelled automatically with the widget. */
	interval(callback: () => void, delayMs: number): number {
		const handle = window.setInterval(callback, Math.max(1, delayMs))
		this.add(() => window.clearInterval(handle))
		return handle
	}

	dispose(): void {
		if (this.disposed) return
		this.disposed = true
		for (const dispose of [...this.disposables]) dispose()
		this.disposables.clear()
	}
}

export interface OverlayWidgetConfig {
	id: string
	plugin: string
	widget: string
	name: string
	size: { width: number; height: number }
	position: { x: number; y: number }
	config: Record<string, any>
	locked: boolean
	visible: boolean
}

export interface OverlayConfig {
	name: string
	schemaVersion?: number
	size: { width: number; height: number }
	widgets: OverlayWidgetConfig[]
	preview?: { offsetX: number; offsetY: number; source?: string }
}

export interface OverlayEventMap {
	[event: string]: unknown
}

export interface OverlayCommandMap {
	[command: string]: { args: unknown; result: unknown }
}

export interface OverlayTransportMessage {
	requestId?: string
	responseId?: string
	name?: string
	args?: unknown[]
	result?: unknown
	failed?: unknown
}

export type OverlayTransportStatus = "idle" | "connecting" | "connected" | "reconnecting"

export interface OverlayTransport {
	connect(): Promise<void>
	close(): Promise<void>
	send(message: OverlayTransportMessage): void
	onMessage(listener: (message: OverlayTransportMessage) => void): Unsubscribe
	onStatus?(listener: (status: OverlayTransportStatus) => void): Unsubscribe
}

export type OverlayProtocolKind = "response" | "config" | "event" | "command" | "state" | "viewer-data" | "audio" | "unknown"

export interface NormalizedOverlayMessage extends OverlayTransportMessage {
	kind: OverlayProtocolKind
}

/**
 * Keeps the legacy Dart message names at the transport boundary. Widgets and
 * the runtime can use the normalized kind without knowing how the old RPC
 * bridge names its messages.
 */
export class LegacyOverlayProtocolAdapter {
	normalize(message: OverlayTransportMessage): NormalizedOverlayMessage {
		if (message.responseId) return { ...message, kind: "response" }

		const kind: OverlayProtocolKind = (() => {
			switch (message.name) {
				case "overlays_setConfig": return "config"
				case "overlays_widget":
				case "overlays_broadcast": return "event"
				case "overlays_widgetRPC": return "command"
				case "overlays_stateUpdate":
				case "overlays_acquireState":
				case "overlays_freeState": return "state"
				case "overlays_onNewViewerData":
				case "overlays_onViewerDataChanged":
				case "overlays_onViewerDataRemoved":
				case "overlays_onNewViewerVariable":
				case "overlays_onViewerVariableDeleted": return "viewer-data"
				case "overlays_playAudio":
				case "overlays_cancelAudio": return "audio"
				default: return "unknown"
			}
		})()

		return { ...message, kind }
	}
}

export interface StateAccess {
	get<T = unknown>(pluginId: string, stateId: string): T | undefined
	watch<T = unknown>(pluginId: string, stateId: string, handler: (value: T | undefined) => void): Unsubscribe
}

export interface ViewerDataRow {
	[variable: string]: any
}

export interface ViewerVariable {
	name: string
	schema?: unknown
}

export interface ViewerDataObserver {
	onNewViewerData?(provider: string, id: string, row: ViewerDataRow): void
	onViewerDataChanged?(provider: string, id: string, variable: string, value: unknown): void
	onViewerDataRemoved?(provider: string, id: string): void
	onNewViewerVariable?(variable: ViewerVariable): void
	onViewerVariableDeleted?(variable: string): void
}

export interface ViewerDataAccess {
	observe(observer: ViewerDataObserver): Unsubscribe
	query(start: number, end: number, sortBy?: string, sortOrder?: number): Promise<ViewerDataRow[]>
	getVariables(): Promise<ViewerVariable[]>
}

export interface WidgetBridge {
	readonly overlayId: string
	readonly widgetId: string
	getConfig(): OverlayWidgetConfig
	onEvent<K extends keyof OverlayEventMap>(type: K, handler: (event: OverlayEventMap[K]) => void): Unsubscribe
	exposeCommand<K extends keyof OverlayCommandMap>(
		command: K,
		handler: (args: OverlayCommandMap[K]["args"]) => OverlayCommandMap[K]["result"] | Promise<OverlayCommandMap[K]["result"]>
	): Unsubscribe
	watchState<T>(pluginId: string, stateId: string, handler: (value: T | undefined) => void): Unsubscribe
	getState<T = unknown>(pluginId: string, stateId: string): T | undefined
	acquireState(pluginId: string, stateId: string): void
	releaseState(pluginId: string, stateId: string): void
	callRPC<T = unknown>(id: string, ...args: unknown[]): Promise<T>
	observeViewerData(observer: ViewerDataObserver): Unsubscribe
	queryViewerData(start: number, end: number, sortBy?: string, sortOrder?: number): Promise<ViewerDataRow[]>
	getViewerVariables(): Promise<ViewerVariable[]>
	playSound(mediaFile: string): void
}

export interface WidgetContext {
	readonly overlayId: string
	readonly widgetId: string
	readonly scope: WidgetScope
	readonly bridge: WidgetBridge
	readonly state: StateAccess
	readonly viewerData: ViewerDataAccess
	readonly isEditor: boolean
	mediaUrl(mediaFile: string): string
}

export interface OverlayWidget<Config = Record<string, any>> {
	mount(container: HTMLElement, config: Config, context: WidgetContext): void
	update(config: Config): void
	destroy(): void
}

export interface OverlayConfigSchema {
	readonly [key: string]: unknown
}

export interface OverlayWidgetDefinition<Config = Record<string, any>> {
	readonly id: string
	readonly name: string
	readonly description?: string
	readonly icon?: string
	readonly defaultSize: { width: number | "canvas"; height: number | "canvas" }
	readonly config: OverlayConfigSchema
	readonly capabilities?: {
		readonly commands?: readonly string[]
		readonly events?: readonly string[]
		readonly states?: readonly string[]
		readonly resizable?: boolean
		readonly aspectRatioLocked?: boolean
	}
	create(context: WidgetContext, config: Config): OverlayWidget<Config>
}

/** Runtime-only contribution exported by a plugin package.
 *
 * Display metadata is deliberately not part of this shape. It is owned by
 * the generated catalog so the browser and Flutter cannot drift apart.
 */
export interface OverlayWidgetFactory {
	readonly id: string
	create(context: WidgetContext, config: Record<string, any>): OverlayWidget<Record<string, any>>
}

export interface OverlayPluginFactories {
	readonly pluginId: string
	readonly widgets: readonly OverlayWidgetFactory[]
}

export interface OverlayPluginContribution {
	readonly pluginId: string
	readonly widgets: readonly OverlayWidgetDefinition[]
}

export interface OverlayWidgetManifest {
	readonly id: string
	readonly name: string
	readonly description?: string
	readonly icon?: string
	readonly defaultSize: { width: number | "canvas"; height: number | "canvas" }
	readonly config: OverlayConfigSchema
	readonly capabilities?: OverlayWidgetDefinition["capabilities"]
}

export interface OverlayPluginManifest {
	readonly pluginId: string
	readonly widgets: readonly OverlayWidgetManifest[]
}

export function defineOverlayWidget<Config>(factory: OverlayWidgetFactory) {
	return factory
}

export function defineOverlayPlugin(contribution: OverlayPluginFactories) {
	return contribution
}

export function bindOverlayPlugin(
	manifest: OverlayPluginManifest,
	factories: OverlayPluginFactories,
): OverlayPluginContribution {
	if (manifest.pluginId !== factories.pluginId) {
		throw new Error(`Overlay plugin ID mismatch: ${manifest.pluginId} !== ${factories.pluginId}`)
	}

	const factoryById = new Map(factories.widgets.map((factory) => [factory.id, factory]))
	const widgets = manifest.widgets.map((metadata) => {
		const factory = factoryById.get(metadata.id)
		if (!factory) throw new Error(`Missing overlay widget factory: ${manifest.pluginId}.${metadata.id}`)
		return { ...metadata, create: factory.create }
	})

	for (const factory of factories.widgets) {
		if (!manifest.widgets.some((metadata) => metadata.id === factory.id)) {
			throw new Error(`Undeclared overlay widget factory: ${manifest.pluginId}.${factory.id}`)
		}
	}

	return { pluginId: manifest.pluginId, widgets }
}

/** Compatibility name used by older plugin packages while they are migrated. */
export const definePluginOverlays = defineOverlayPlugin

export function applyStyles(element: HTMLElement, styles: CSSProperties): void {
	for (const [property, value] of Object.entries(styles)) {
		if (value === undefined) continue
		const cssProperty = property.replace(/[A-Z]/g, (match) => `-${match.toLowerCase()}`)
		element.style.setProperty(cssProperty, String(value))
	}
}

export function createElement<K extends keyof HTMLElementTagNameMap>(tag: K, className?: string): HTMLElementTagNameMap[K] {
	const element = document.createElement(tag)
	if (className) element.className = className
	return element
}

export function clearElement(element: HTMLElement): void {
	while (element.firstChild) element.removeChild(element.firstChild)
}

export function toRgba(hex: string, opacity: number, fallback: [number, number, number] = [13, 17, 23]): string {
	const match = String(hex || "").match(/^#?([0-9a-f]{6})$/i)
	const value = match ? Number.parseInt(match[1], 16) : fallback[0] * 65536 + fallback[1] * 256 + fallback[2]
	return `rgba(${(value >> 16) & 255}, ${(value >> 8) & 255}, ${value & 255}, ${Math.max(0, Math.min(1, Number(opacity) || 0))})`
}

export function mediaUrl(host: string, mediaFile: string): string {
	const value = String(mediaFile || "").trim()
	if (!value) return ""
	if (/^https?:\/\//i.test(value)) return value
	const normalized = value.replaceAll("\\", "/").replace(/^\/+/, "")
	if (normalized.startsWith("media/")) return `http://${host}/${normalized}`
	return `http://${host}/media/${normalized}`
}

export interface MediaPlaybackOptions {
	playId?: string
	startSec?: number
	endSec?: number
	volume?: number
}

export function playMedia(host: string, mediaFile: string, options: MediaPlaybackOptions = {}): HTMLAudioElement | undefined {
	if (!mediaFile) return undefined
	const audio = new Audio(mediaUrl(host, mediaFile))
	if (options.volume !== undefined) audio.volume = Math.max(0, Math.min(1, Number(options.volume) / 100))
	if (options.startSec !== undefined && Number.isFinite(options.startSec)) audio.currentTime = Math.max(0, options.startSec)
	if (options.endSec !== undefined && Number.isFinite(options.endSec)) {
		audio.addEventListener("timeupdate", () => {
			if (audio.currentTime >= options.endSec!) audio.pause()
		})
	}
	audio.addEventListener("canplaythrough", () => void audio.play(), { once: true })
	return audio
}
