import {
	ComputedRef,
	MaybeRefOrGetter,
	computed,
	inject,
	onBeforeUnmount,
	onMounted,
	ref,
	toValue,
	watch,
	watchEffect,
} from "vue"
import { DashboardConfig, DashboardWidget } from "ShowRunner-plugin-dashboards-shared"

export interface ShowRunnerBridgeImplementation {
	acquireState(plugin: string, state: string): void
	releaseState(plugin: string, state: string): void
	state: { readonly value: Record<string, Record<string, any>> }
	config: { readonly value: DashboardWidget }
	registerRPC(id: string, func: (...args: any[]) => any): void
	unregisterRPC(id: string): void
	registerMessage(id: string, func: (...args: any[]) => any): void
	unregisterMessage(id: string, func: (...args: any[]) => any): void

	callRPC(id: string, ...args: any[]): Promise<any>
}

export function useShowRunnerBridge(): ShowRunnerBridgeImplementation {
	return inject<ShowRunnerBridgeImplementation>("ShowRunner-bridge", {
		acquireState(plugin, state) {},
		releaseState(plugin, state) {},
		state: { value: {} },
		config: computed<DashboardWidget>(() => ({
			id: "error",
			plugin: "error",
			widget: "error",
			name: "error",
			size: { width: 0, height: 0 },
			position: { x: 0, y: 0 },
			config: {},
			visible: false,
			locked: false,
		})),
		registerRPC(id, func) {},
		unregisterRPC(id) {},
		registerMessage(id, func) {},
		unregisterMessage(id) {},
		async callRPC(id, ...args) {},
	})
}

export function useShowRunnerState<T = any>(
	plugin: MaybeRefOrGetter<string>,
	state: MaybeRefOrGetter<string>
): ComputedRef<T> {
	const bridge = useShowRunnerBridge()

	onMounted(() => {
		//Acquire
		watch(
			() => ({
				p: toValue(plugin),
				s: toValue(state),
			}),
			(newConfig, oldConfig) => {
				if (oldConfig) {
					bridge.releaseState(oldConfig.p, oldConfig.s)
				}

				bridge.acquireState(newConfig.p, newConfig.s)
			},
			{ immediate: true, deep: true }
		)
	})

	onBeforeUnmount(() => {
		bridge.releaseState(toValue(plugin), toValue(state))
	})

	return computed<T>(() => {
		return bridge.state.value[toValue(plugin)]?.[toValue(state)] as T
	})
}

export function handleDashboardRPC(id: string, func: (...args: any[]) => any) {
	const bridge = useShowRunnerBridge()

	onMounted(() => {
		bridge.registerRPC(id, func)
	})

	onBeforeUnmount(() => {
		bridge.unregisterRPC(id)
	})
}

export function useCallDashboardRPC<T extends (...args: any) => any>(id: string) {
	const bridge = useShowRunnerBridge()

	return async (...args: Parameters<T>): Promise<ReturnType<T>> => {
		const result = await bridge.callRPC(id, ...args)
		return result as ReturnType<T>
	}
}
