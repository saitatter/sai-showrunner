<template>
	<div
		class="scene-banner"
		:class="{ active: activeScene }"
		:style="{
			'--scene-accent': activeScene?.accentColor || config.accentColor,
			'--scene-bg': toRgba(config.backgroundColor, config.backgroundOpacity),
			'--scene-font': config.fontFamily,
		}"
	>
		<div class="scene-banner__rule" />
		<div>
			<strong>{{ activeScene?.title || config.previewTitle }}</strong>
			<span>{{ activeScene?.subtitle || config.previewSubtitle }}</span>
		</div>
	</div>
</template>

<script setup lang="ts">
import { onMounted, ref } from "vue"
import { declareWidgetOptions, handleOverlayMessage, useShowRunnerBridge, useIsEditor } from "showrunner-overlay-core"

interface SceneEvent {
	type?: "scene.begin" | "scene.end"
	targetOverlayId?: string
	targetWidgetId?: string
	sceneKey?: string
	title?: string
	subtitle?: string
	accentColor?: string
}

defineOptions({
	widget: declareWidgetOptions({
		id: "sceneBanner",
		name: "Scene Banner",
		description: "Displays scene begin/end automation events as an overlay banner.",
		icon: "mdi mdi-motion-play-outline",
		defaultSize: { width: 900, height: 170 },
		config: {
			type: Object,
			properties: {
				fontFamily: { type: String, name: "Font Family", default: "Inter, Arial, sans-serif", required: true },
				accentColor: { type: String, name: "Accent Color", default: "#9146ff", required: true },
				backgroundColor: { type: String, name: "Background Color", default: "#101010", required: true },
				backgroundOpacity: { type: Number, name: "Background Opacity", default: 0.82, required: true },
				duration: { type: Number, name: "Duration Seconds", default: 6, required: true },
				previewTitle: { type: String, name: "Preview Title", default: "Starting Soon", required: true },
				previewSubtitle: { type: String, name: "Preview Subtitle", default: "Scene automation preview", required: true },
			},
		},
	}),
})

const props = defineProps<{
	config: {
		fontFamily: string
		accentColor: string
		backgroundColor: string
		backgroundOpacity: number
		duration: number
		previewTitle: string
		previewSubtitle: string
	}
}>()

const isEditor = useIsEditor()
const bridge = useShowRunnerBridge()
const activeScene = ref<SceneEvent>()
let clearTimer = 0

function handleSceneEvent(event: SceneEvent) {
	if (!matchesTarget(event)) return
	window.clearTimeout(clearTimer)
	if (event.type === "scene.end") {
		activeScene.value = undefined
		return
	}

	activeScene.value = event
	const durationMs = Math.max(1, Number(props.config.duration) || 6) * 1000
	if (!isEditor.value) {
		clearTimer = window.setTimeout(() => {
			activeScene.value = undefined
		}, durationMs)
	}
}

function matchesTarget(event: SceneEvent) {
	if (isEditor.value) return true
	if (event.targetOverlayId && event.targetOverlayId !== bridge.config.value.overlayId) return false
	if (event.targetWidgetId && event.targetWidgetId !== bridge.config.value.id) return false
	return true
}

function toRgba(hex: string, opacity: number) {
	const match = String(hex || "").match(/^#?([0-9a-f]{6})$/i)
	if (!match) return `rgba(16, 16, 16, ${Number(opacity) || 0.82})`
	const value = Number.parseInt(match[1], 16)
	return `rgba(${(value >> 16) & 255}, ${(value >> 8) & 255}, ${value & 255}, ${Math.max(
		0,
		Math.min(1, Number(opacity) || 0)
	)})`
}

handleOverlayMessage("showrunner_scene_event", handleSceneEvent)

onMounted(() => {
	if (!isEditor.value) return
	activeScene.value = {
		type: "scene.begin",
		title: props.config.previewTitle,
		subtitle: props.config.previewSubtitle,
		accentColor: props.config.accentColor,
	}
})
</script>

<style scoped>
.scene-banner {
	align-items: center;
	background: var(--scene-bg);
	border: 1px solid color-mix(in srgb, var(--scene-accent), transparent 25%);
	border-radius: 8px;
	box-shadow: 0 16px 60px rgba(0, 0, 0, 0.35);
	color: #fff;
	display: grid;
	font-family: var(--scene-font);
	gap: 1rem;
	grid-template-columns: 0.45rem 1fr;
	height: 100%;
	opacity: 0;
	padding: 1.1rem 1.3rem;
	transform: translateY(12px);
	transition:
		opacity 160ms ease,
		transform 160ms ease;
	width: 100%;
}

.scene-banner.active,
.scene-banner:has(strong) {
	opacity: 1;
	transform: translateY(0);
}

.scene-banner__rule {
	background: var(--scene-accent);
	border-radius: 999px;
	height: 100%;
	min-height: 5rem;
}

.scene-banner strong {
	color: var(--scene-accent);
	display: block;
	font-size: 2rem;
	line-height: 1.05;
}

.scene-banner span {
	color: rgba(255, 255, 255, 0.82);
	display: block;
	font-size: 1.1rem;
	margin-top: 0.35rem;
}
</style>
