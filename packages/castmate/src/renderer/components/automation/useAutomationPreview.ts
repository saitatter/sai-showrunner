import { computed, ref, type ComputedRef, type Ref } from "vue"
import { findActionAndSequenceById, isActionStack, type AutomationConfig } from "castmate-schema"
import { usePluginStore } from "castmate-ui-core"

interface PreviewNode {
	id: string
	title: string
}

const PREVIEW_DEFAULT_STEP_SECONDS = 0.9
const PREVIEW_TICK_MS = 100

export function useAutomationPreview(model: Ref<AutomationConfig>, previewNodes: ComputedRef<PreviewNode[]>) {
	const pluginStore = usePluginStore()
	const playheadNodeId = ref<string>()
	const isPreviewPlaying = ref(false)
	const playheadElapsedMs = ref(0)
	let playheadTimer: ReturnType<typeof window.setInterval> | undefined
	let playheadStartedAt = 0

	const previewSteps = computed(() => {
		let startMs = 0
		return previewNodes.value.map((node) => {
			const durationMs = getPreviewNodeDurationMs(node.id)
			const step = {
				node,
				startMs,
				durationMs,
				endMs: startMs + durationMs,
			}
			startMs += durationMs
			return step
		})
	})
	const previewTotalMs = computed(() => Math.max(0, previewSteps.value.at(-1)?.endMs ?? 0))
	const playheadProgress = computed(() => {
		if (!previewTotalMs.value) return 0
		return Math.min(100, Math.max(0, (playheadElapsedMs.value / previewTotalMs.value) * 100))
	})
	const currentPreviewStep = computed(() => {
		if (!previewSteps.value.length) return undefined
		return (
			previewSteps.value.find((step) => playheadElapsedMs.value >= step.startMs && playheadElapsedMs.value < step.endMs) ??
			previewSteps.value.at(-1)
		)
	})
	const playheadElapsedLabel = computed(() => formatSeconds(playheadElapsedMs.value / 1000))
	const previewTotalLabel = computed(() => formatSeconds(previewTotalMs.value / 1000))

	function getConfiguredDurationSeconds(actionId: string) {
		const actionInfo = findActionAndSequenceById(actionId, model.value)
		const action = actionInfo?.action
		if (!action || isActionStack(action)) return undefined

		const configuredDuration = Number(action.config?.duration)
		if (Number.isFinite(configuredDuration) && configuredDuration > 0) return configuredDuration

		const actionDefinition = pluginStore.pluginMap.get(action.plugin)?.actions[action.action]
		const duration = actionDefinition?.duration
		if (!duration || "ipcCallback" in duration) return undefined
		if (duration.dragType === "fixed" && Number.isFinite(duration.duration)) return duration.duration
		if (duration.dragType === "length" && duration.rightSlider?.sliderProp) {
			const value = Number(action.config?.[duration.rightSlider.sliderProp])
			if (Number.isFinite(value) && value > 0) return value
		}
		if (duration.dragType === "crop" && Number.isFinite(duration.duration)) return duration.duration
		return undefined
	}

	function getPreviewNodeDurationMs(nodeId: string) {
		const actionInfo = findActionAndSequenceById(nodeId, model.value)
		const action = actionInfo?.action
		if (!action) return PREVIEW_DEFAULT_STEP_SECONDS * 1000
		if (isActionStack(action)) return Math.max(PREVIEW_DEFAULT_STEP_SECONDS, action.stack.length * 0.35) * 1000
		return (getConfiguredDurationSeconds(nodeId) ?? PREVIEW_DEFAULT_STEP_SECONDS) * 1000
	}

	function togglePlayheadPreview() {
		if (isPreviewPlaying.value) {
			pausePlayheadPreview()
			return
		}

		if (!previewSteps.value.length) return
		if (playheadElapsedMs.value >= previewTotalMs.value) playheadElapsedMs.value = 0
		isPreviewPlaying.value = true
		playheadStartedAt = performance.now() - playheadElapsedMs.value
		updatePlayheadPreview()
		playheadTimer = window.setInterval(updatePlayheadPreview, PREVIEW_TICK_MS)
	}

	function pausePlayheadPreview() {
		isPreviewPlaying.value = false
		if (playheadTimer) {
			window.clearInterval(playheadTimer)
			playheadTimer = undefined
		}
	}

	function resetPlayheadPreview() {
		pausePlayheadPreview()
		playheadElapsedMs.value = 0
		playheadNodeId.value = undefined
	}

	function updatePlayheadPreview() {
		const totalMs = previewTotalMs.value
		if (!totalMs) {
			resetPlayheadPreview()
			return
		}

		playheadElapsedMs.value = Math.min(totalMs, performance.now() - playheadStartedAt)
		playheadNodeId.value = currentPreviewStep.value?.node.id

		if (playheadElapsedMs.value >= totalMs) {
			pausePlayheadPreview()
		}
	}

	return {
		playheadNodeId,
		isPreviewPlaying,
		playheadProgress,
		currentPreviewStep,
		playheadElapsedLabel,
		previewTotalLabel,
		togglePlayheadPreview,
		pausePlayheadPreview,
		resetPlayheadPreview,
		getConfiguredDurationSeconds,
	}
}

function formatSeconds(value: number) {
	return `${Number(value.toFixed(2))}s`
}
