import { computed, type ComputedRef, type Ref } from "vue"
import { nanoid } from "nanoid"
import { constructDefault, type AutomationConfig, type AutomationTriggerNode } from "showrunner-schema"
import type { NodePosition } from "./useNodeCanvas"
import type { NodeData } from "./useNodeRendering"

interface TriggerDefinition {
	name?: string
	icon?: string
	config?: unknown
	context?: unknown | ((config: unknown) => unknown | Promise<unknown>)
}

interface PluginLike {
	color?: string
	triggers?: Record<string, TriggerDefinition>
}

interface PluginStoreLike {
	pluginMap: Map<string, PluginLike>
}

interface UseGraphTriggerNodesOptions {
	model: Ref<AutomationConfig>
	selectedNode: ComputedRef<NodeData | undefined>
	selectedNodeId: Ref<string | undefined>
	pluginStore: PluginStoreLike
	getContextMenuCanvasPoint: () => NodePosition
	trackRecentlyUsed: (key: string, kind: "action" | "trigger", name: string, icon: string, color: string) => void
	focusNode: (nodeId: string) => void
	closeContextMenu: () => void
	commitUndo: () => void
	configOpen: Ref<boolean>
}

export function useGraphTriggerNodes({
	model,
	selectedNode,
	selectedNodeId,
	pluginStore,
	getContextMenuCanvasPoint,
	trackRecentlyUsed,
	focusNode,
	closeContextMenu,
	commitUndo,
	configOpen,
}: UseGraphTriggerNodesOptions) {
	const selectedTriggerNode = computed(() => {
		if (selectedNode.value?.kind !== "trigger") return undefined
		const triggerNodes = model.value.triggerNodes ?? []
		const triggerNode = triggerNodes.find((node) => node.id === selectedNode.value?.id)
		if (triggerNode) return triggerNode
		if (selectedNode.value.id !== "trigger") return undefined
		return {
			id: "trigger",
			plugin: model.value.plugin,
			trigger: model.value.trigger,
			config: model.value.config ?? {},
			stop: model.value.stop,
			x: 42,
			y: 88,
		} satisfies AutomationTriggerNode
	})

	const selectedTriggerConfigModel = computed({
		get() {
			const triggerNode = selectedTriggerNode.value
			if (!triggerNode) return undefined
			return {
				...triggerNode,
				testContext: model.value.testContext,
			}
		},
		set(next) {
			if (!next || !selectedNodeId.value) return
			upsertTriggerNode({
				id: next.id ?? selectedNodeId.value,
				plugin: next.plugin,
				trigger: next.trigger,
				config: next.config ?? {},
				stop: next.stop,
				x: typeof next.x === "number" ? next.x : selectedNode.value?.x ?? 42,
				y: typeof next.y === "number" ? next.y : selectedNode.value?.y ?? 88,
			})
			model.value.testContext = next.testContext
		},
	})

	const selectedTriggerMissing = computed(() => {
		const trigger = selectedTriggerConfigModel.value
		if (!trigger) return false
		if (!trigger.plugin || !trigger.trigger) return false
		return !pluginStore.pluginMap.get(trigger.plugin)?.triggers?.[trigger.trigger]
	})

	function upsertTriggerNode(triggerNode: AutomationTriggerNode) {
		model.value.triggerNodes ??= []
		const index = model.value.triggerNodes.findIndex((node) => node.id === triggerNode.id)
		if (index >= 0) {
			model.value.triggerNodes[index] = triggerNode
		} else {
			model.value.triggerNodes.push(triggerNode)
		}

		if (index <= 0 && model.value.triggerNodes[0]?.id === triggerNode.id) {
			Object.assign(model.value, {
				plugin: triggerNode.plugin,
				trigger: triggerNode.trigger,
				config: triggerNode.config,
				stop: triggerNode.stop ?? false,
			})
		}
	}

	async function selectTriggerFromContext(triggerKey: string) {
		const [pluginId, triggerId] = triggerKey.split(":")
		const plugin = pluginStore.pluginMap.get(pluginId)
		const trigger = plugin?.triggers?.[triggerId]
		if (!pluginId || !triggerId || !trigger) return

		trackRecentlyUsed(triggerKey, "trigger", trigger.name ?? triggerId, trigger.icon ?? "mdi mdi-flash", String(plugin?.color ?? "#e9aaff"))

		const nextConfig = await constructDefault(trigger.config)
		const contextSchema = typeof trigger.context === "function" ? await trigger.context(nextConfig) : trigger.context

		model.value.testContext = contextSchema ? await constructDefault(contextSchema) : model.value.testContext
		model.value.triggerNodes ??= []
		const selectedTrigger = selectedNode.value?.kind === "trigger" ? selectedTriggerNode.value : undefined
		const existingIndex = selectedTrigger ? model.value.triggerNodes.findIndex((node) => node.id === selectedTrigger.id) : -1
		const shouldReplaceSelected = Boolean(selectedTrigger && existingIndex >= 0)
		const shouldInitializeLegacy = !shouldReplaceSelected && model.value.triggerNodes.length === 0 && !model.value.plugin && !model.value.trigger
		const point = getContextMenuCanvasPoint()
		const triggerNode: AutomationTriggerNode = {
			id: shouldReplaceSelected ? selectedTrigger!.id : shouldInitializeLegacy ? "trigger" : `trigger:${nanoid()}`,
			plugin: pluginId,
			trigger: triggerId,
			config: nextConfig,
			stop: shouldReplaceSelected ? selectedTrigger?.stop ?? false : false,
			x: shouldReplaceSelected ? selectedTrigger!.x : point.x,
			y: shouldReplaceSelected ? selectedTrigger!.y : point.y,
		}
		upsertTriggerNode(triggerNode)

		focusNode(triggerNode.id)
		configOpen.value = true
		closeContextMenu()
		commitUndo()
	}

	return {
		selectedTriggerConfigModel,
		selectedTriggerMissing,
		selectTriggerFromContext,
	}
}
