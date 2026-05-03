<template>
	<div
		class="paid-alert"
		:class="{ active: Boolean(activeAlert) }"
		:style="{
			'--paid-alert-accent': config.accentColor,
			'--paid-alert-bg': toRgba(config.backgroundColor, config.backgroundOpacity),
			'--paid-alert-font': config.fontFamily,
		}"
	>
		<div class="paid-alert__shine" />
		<div class="paid-alert__icon">
			<i class="mdi mdi-cash-star" />
		</div>
		<div class="paid-alert__body">
			<strong>{{ activeAlert?.title || config.previewTitle }}</strong>
			<span>{{ activeAlert?.displayName || config.previewViewer }}</span>
			<p>{{ activeAlert?.message || config.previewMessage }}</p>
		</div>
		<div class="paid-alert__amount">{{ amountLabel }}</div>
	</div>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from "vue"
import { declareWidgetOptions, handleOverlayMessage, useShowRunnerBridge, useIsEditor } from "showrunner-overlay-core"

interface PaidAlertMessage {
	id?: string
	targetOverlayId?: string
	targetWidgetId?: string
	platform?: string
	displayName?: string
	amount?: string
	currency?: string
	title?: string
	message?: string
}

defineOptions({
	widget: declareWidgetOptions({
		id: "paidAlert",
		name: "Paid Alert",
		description: "Displays YouTube paid messages, donations, and other support events pushed by automations.",
		icon: "mdi mdi-cash-star",
		defaultSize: { width: 680, height: 190 },
		config: {
			type: Object,
			properties: {
				fontFamily: { type: String, name: "Font Family", default: "Inter, Arial, sans-serif", required: true },
				accentColor: { type: String, name: "Accent Color", default: "#ffd166", required: true },
				backgroundColor: { type: String, name: "Background Color", default: "#131313", required: true },
				backgroundOpacity: { type: Number, name: "Background Opacity", default: 0.86, required: true },
				duration: { type: Number, name: "Duration Seconds", default: 7, required: true },
				previewTitle: { type: String, name: "Preview Title", default: "Super Chat", required: true },
				previewViewer: { type: String, name: "Preview Viewer", default: "Supporter", required: true },
				previewMessage: { type: String, name: "Preview Message", default: "Thanks for the stream!", required: true },
				previewAmount: { type: String, name: "Preview Amount", default: "10.00", required: true },
				previewCurrency: { type: String, name: "Preview Currency", default: "USD", required: true },
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
		previewViewer: string
		previewMessage: string
		previewAmount: string
		previewCurrency: string
	}
}>()

const isEditor = useIsEditor()
const bridge = useShowRunnerBridge()
const activeAlert = ref<PaidAlertMessage>()
let clearTimer = 0

const amountLabel = computed(() => {
	const amount = activeAlert.value?.amount || props.config.previewAmount
	const currency = activeAlert.value?.currency || props.config.previewCurrency
	return [amount, currency].filter(Boolean).join(" ")
})

function showAlert(message: PaidAlertMessage) {
	if (!matchesTarget(message)) return
	activeAlert.value = message
	window.clearTimeout(clearTimer)
	const durationMs = Math.max(1, Number(props.config.duration) || 7) * 1000
	if (!isEditor.value) {
		clearTimer = window.setTimeout(() => {
			activeAlert.value = undefined
		}, durationMs)
	}
}

function matchesTarget(message: PaidAlertMessage) {
	if (isEditor.value) return true
	if (message.targetOverlayId && message.targetOverlayId !== bridge.config.value.overlayId) return false
	if (message.targetWidgetId && message.targetWidgetId !== bridge.config.value.id) return false
	return true
}

function toRgba(hex: string, opacity: number) {
	const match = String(hex || "").match(/^#?([0-9a-f]{6})$/i)
	if (!match) return `rgba(19, 19, 19, ${Number(opacity) || 0.86})`
	const value = Number.parseInt(match[1], 16)
	return `rgba(${(value >> 16) & 255}, ${(value >> 8) & 255}, ${value & 255}, ${Math.max(
		0,
		Math.min(1, Number(opacity) || 0)
	)})`
}

handleOverlayMessage("showrunner_paid_alert", showAlert)

onMounted(() => {
	if (!isEditor.value) return
	showAlert({
		id: "preview",
		platform: "youtube",
		displayName: props.config.previewViewer,
		title: props.config.previewTitle,
		message: props.config.previewMessage,
		amount: props.config.previewAmount,
		currency: props.config.previewCurrency,
	})
})
</script>

<style scoped>
.paid-alert {
	align-items: center;
	background: var(--paid-alert-bg);
	border: 2px solid color-mix(in srgb, var(--paid-alert-accent), transparent 15%);
	border-radius: 8px;
	box-shadow: 0 18px 55px rgba(0, 0, 0, 0.34);
	color: white;
	display: grid;
	font-family: var(--paid-alert-font);
	gap: 1rem;
	grid-template-columns: auto 1fr auto;
	height: 100%;
	opacity: 0;
	overflow: hidden;
	padding: 1rem 1.2rem;
	position: relative;
	transform: translateY(14px) scale(0.98);
	transition:
		opacity 180ms ease,
		transform 180ms ease;
	width: 100%;
}

.paid-alert.active,
.paid-alert:has(.paid-alert__body) {
	opacity: 1;
	transform: translateY(0) scale(1);
}

.paid-alert__shine {
	background: linear-gradient(120deg, transparent, color-mix(in srgb, var(--paid-alert-accent), transparent 72%), transparent);
	inset: 0;
	position: absolute;
	transform: translateX(-35%);
}

.paid-alert__icon {
	align-items: center;
	background: var(--paid-alert-accent);
	border-radius: 999px;
	color: #161616;
	display: flex;
	font-size: 2rem;
	height: 4.2rem;
	justify-content: center;
	width: 4.2rem;
	z-index: 1;
}

.paid-alert__body {
	display: grid;
	gap: 0.2rem;
	min-width: 0;
	z-index: 1;
}

.paid-alert__body strong {
	color: var(--paid-alert-accent);
	font-size: 1.45rem;
}

.paid-alert__body span {
	font-size: 1.1rem;
	font-weight: 800;
}

.paid-alert__body p {
	font-size: 1rem;
	margin: 0;
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.paid-alert__amount {
	color: var(--paid-alert-accent);
	font-size: 1.25rem;
	font-weight: 900;
	z-index: 1;
}
</style>
