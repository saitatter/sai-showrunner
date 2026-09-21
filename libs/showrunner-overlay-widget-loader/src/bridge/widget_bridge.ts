import {
	OverlayWidgetConfig,
	Unsubscribe,
	WidgetBridge,
	WidgetScope,
	playMedia,
} from "showrunner-overlay-core"
import { StateStore } from "../state/state_store"
import { ViewerDataStore } from "../viewer_data/viewer_data_store"

export interface WidgetBridgeHost {
	readonly overlayId: string
	readonly host?: string
	readonly stateStore: StateStore
	readonly viewerData: ViewerDataStore
	getConfig(): OverlayWidgetConfig
	onEvent(
		type: string,
		widgetId: string,
		handler: (event: unknown) => void,
		scope: WidgetScope,
	): Unsubscribe
	exposeCommand(
		key: string,
		handler: (args: unknown) => unknown | Promise<unknown>,
		scope: WidgetScope,
	): Unsubscribe
	callBackend<T = unknown>(name: string, ...args: unknown[]): Promise<T>
}

/** Creates the typed bridge exposed to one widget instance.
 *
 * All subscriptions and media handles are registered in the instance scope,
 * so removing a widget does not require the runtime to know each individual
 * cleanup source.
 */
export function createWidgetBridge(
	host: WidgetBridgeHost,
	config: OverlayWidgetConfig,
	scope: WidgetScope,
): WidgetBridge {
	return {
		overlayId: host.overlayId,
		widgetId: config.id,
		getConfig: host.getConfig,
		onEvent: (type, handler) => {
			const key = String(type)
			return host.onEvent(key, config.id, handler as (event: unknown) => void, scope)
		},
		exposeCommand: (command, handler) => {
			const key = `${config.id}.${String(command)}`
			return host.exposeCommand(
				key,
				handler as (args: unknown) => unknown | Promise<unknown>,
				scope,
			)
		},
		watchState: (pluginId, stateId, handler) =>
			scope.add(host.stateStore.watch(pluginId, stateId, handler)),
		getState: (pluginId, stateId) => host.stateStore.get(pluginId, stateId),
		acquireState: (pluginId, stateId) => {
			host.stateStore.acquire(pluginId, stateId)
			scope.add(() => host.stateStore.release(pluginId, stateId))
		},
		releaseState: (pluginId, stateId) => host.stateStore.release(pluginId, stateId),
		callRPC: (id, ...args) => host.callBackend("overlays_widgetRPC", id, config.id, ...args),
		observeViewerData: (observer) => scope.add(host.viewerData.observe(observer)),
		queryViewerData: (start, end, sortBy, sortOrder) =>
			host.viewerData.query(start, end, sortBy, sortOrder),
		getViewerVariables: () => host.viewerData.getVariables(),
		playSound: (file) => {
			const audio = playMedia(host.host ?? window.location.host, file)
			if (audio) scope.add(() => audio.pause())
		},
	}
}
