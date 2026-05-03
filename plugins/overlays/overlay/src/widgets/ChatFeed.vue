<template>
	<div
		class="chat-feed"
		:class="`chat-feed--${config.orientation}`"
		:style="{
			'--chat-font-family': config.fontFamily,
			'--chat-font-size': `${config.fontSize}px`,
			'--chat-bg': toRgba(config.backgroundColor, config.backgroundOpacity),
			'--chat-twitch': config.twitchColor,
			'--chat-youtube': config.youtubeColor,
		}"
	>
		<article v-for="entry in visibleMessages" :key="entry.id" class="chat-feed__message" :data-platform="entry.platform">
			<div class="chat-feed__meta">
				<span class="chat-feed__platform"></span>
				<span v-if="config.showBadges" class="chat-feed__badges">
					<span v-for="badge in entry.badges" :key="badge" class="chat-feed__badge">{{ badge }}</span>
				</span>
				<strong>{{ entry.displayName }}</strong>
			</div>
			<p>{{ entry.message }}</p>
		</article>
	</div>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from "vue"
import { declareWidgetOptions, handleOverlayMessage, useShowRunnerBridge, useIsEditor } from "showrunner-overlay-core"

interface ChatFeedMessage {
	id?: string
	platform?: string
	user?: string
	username?: string
	displayName?: string
	message?: string
	text?: string
	badges?: string[] | string
	targetOverlayId?: string
	targetWidgetId?: string
}

defineOptions({
	widget: declareWidgetOptions({
		id: "chatFeed",
		name: "Chat Feed",
		description: "Displays approved chat messages pushed by ShowRunner automations.",
		icon: "mdi mdi-chat-processing-outline",
		defaultSize: { width: 900, height: 180 },
		config: {
			type: Object,
			properties: {
				fontFamily: { type: String, name: "Font Family", default: "Inter, Arial, sans-serif", required: true },
				fontSize: { type: Number, name: "Font Size", default: 24, required: true },
				backgroundColor: { type: String, name: "Background Color", default: "#0d1117", required: true },
				backgroundOpacity: { type: Number, name: "Background Opacity", default: 0.72, required: true },
				fadeTime: { type: Number, name: "Fade Time Seconds", default: 10, required: true },
				maxMessages: { type: Number, name: "Max Messages", default: 8, required: true },
				orientation: {
					type: String,
					name: "Layout",
					default: "horizontal",
					required: true,
					enum: ["horizontal", "vertical"],
				},
				twitchColor: { type: String, name: "Twitch Color", default: "#9146ff", required: true },
				youtubeColor: { type: String, name: "YouTube Color", default: "#ff0033", required: true },
				showBadges: { type: Boolean, name: "Show Badges", default: true, required: true },
			},
		},
	}),
})

const props = defineProps<{
	config: {
		fontFamily: string
		fontSize: number
		backgroundColor: string
		backgroundOpacity: number
		fadeTime: number
		maxMessages: number
		orientation: "horizontal" | "vertical"
		twitchColor: string
		youtubeColor: string
		showBadges: boolean
	}
}>()

const isEditor = useIsEditor()
const bridge = useShowRunnerBridge()
const messages = ref<Required<ChatFeedMessage>[]>([])
const visibleMessages = computed(() => messages.value.slice(0, Math.max(1, Number(props.config.maxMessages) || 8)))

function addMessage(message: ChatFeedMessage) {
	if (!matchesTarget(message)) return
	const entry = normalizeMessage(message)
	messages.value.unshift(entry)
	messages.value = messages.value.slice(0, Math.max(1, Number(props.config.maxMessages) || 8))

	const fadeMs = Math.max(0, Number(props.config.fadeTime) || 0) * 1000
	if (fadeMs > 0 && !isEditor.value) {
		window.setTimeout(() => {
			messages.value = messages.value.filter((item) => item.id !== entry.id)
		}, fadeMs)
	}
}

function matchesTarget(message: ChatFeedMessage) {
	if (isEditor.value) return true
	if (message.targetOverlayId && message.targetOverlayId !== bridge.config.value.overlayId) return false
	if (message.targetWidgetId && message.targetWidgetId !== bridge.config.value.id) return false
	return true
}

function normalizeMessage(message: ChatFeedMessage): Required<ChatFeedMessage> {
	const badges = Array.isArray(message.badges)
		? message.badges
		: String(message.badges || "")
				.split(",")
				.map((badge) => badge.trim())
				.filter(Boolean)

	return {
		id: String(message.id || `${Date.now()}-${Math.random()}`),
		platform: String(message.platform || "unknown").toLowerCase(),
		user: String(message.user || message.username || message.displayName || "unknown"),
		username: String(message.username || message.user || message.displayName || "unknown"),
		displayName: String(message.displayName || message.username || message.user || "unknown"),
		message: String(message.message || message.text || ""),
		text: String(message.text || message.message || ""),
		badges,
		targetOverlayId: String(message.targetOverlayId || ""),
		targetWidgetId: String(message.targetWidgetId || ""),
	}
}

function toRgba(hex: string, opacity: number) {
	const match = String(hex || "").match(/^#?([0-9a-f]{6})$/i)
	if (!match) return `rgba(13, 17, 23, ${Number(opacity) || 0.72})`
	const value = Number.parseInt(match[1], 16)
	return `rgba(${(value >> 16) & 255}, ${(value >> 8) & 255}, ${value & 255}, ${Math.max(
		0,
		Math.min(1, Number(opacity) || 0)
	)})`
}

handleOverlayMessage("showrunner_chat_message", addMessage)

onMounted(() => {
	if (!isEditor.value) return
	addMessage({
		id: "sample-twitch",
		platform: "twitch",
		displayName: "ViewerName",
		message: "Approved Twitch message preview.",
		badges: ["sub"],
	})
	addMessage({
		id: "sample-youtube",
		platform: "youtube",
		displayName: "Channel Member",
		message: "Approved YouTube message preview.",
		badges: ["member"],
	})
})
</script>

<style scoped>
.chat-feed {
	align-items: flex-end;
	display: flex;
	font-family: var(--chat-font-family);
	font-size: var(--chat-font-size);
	gap: 0.5rem;
	height: 100%;
	overflow: hidden;
	width: 100%;
}

.chat-feed--vertical {
	align-items: stretch;
	flex-direction: column-reverse;
}

.chat-feed__message {
	background: var(--chat-bg);
	border-left: 0.25rem solid var(--chat-twitch);
	border-radius: 6px;
	color: white;
	display: grid;
	flex: 0 0 auto;
	gap: 0.25rem;
	max-width: min(34rem, 100%);
	min-width: 12rem;
	padding: 0.55rem 0.7rem;
}

.chat-feed__message[data-platform="youtube"] {
	border-left-color: var(--chat-youtube);
}

.chat-feed__meta {
	align-items: center;
	display: flex;
	font-size: 0.72em;
	gap: 0.35rem;
	line-height: 1;
	min-width: 0;
}

.chat-feed__meta strong {
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.chat-feed__platform {
	background: currentColor;
	border-radius: 999px;
	color: var(--chat-twitch);
	height: 0.55rem;
	width: 0.55rem;
}

.chat-feed__message[data-platform="youtube"] .chat-feed__platform {
	color: var(--chat-youtube);
}

.chat-feed__badges {
	display: flex;
	gap: 0.2rem;
}

.chat-feed__badge {
	background: rgba(255, 255, 255, 0.14);
	border-radius: 3px;
	font-size: 0.65em;
	padding: 0.08rem 0.2rem;
	text-transform: uppercase;
}

.chat-feed__message p {
	line-height: 1.25;
	margin: 0;
	overflow-wrap: anywhere;
}
</style>
