<template>
	<div class="youtube-page">
		<header class="youtube-page__header">
			<div>
				<p class="youtube-page__eyebrow">Platform Integration</p>
				<h1>YouTube Live</h1>
			</div>
			<div class="youtube-page__actions">
				<button class="youtube-page__button youtube-page__button--secondary" type="button" :disabled="busy" @click="connect">
					Connect
				</button>
				<button class="youtube-page__button youtube-page__button--secondary" type="button" :disabled="busy" @click="toggleLiveChat">
					{{ status.liveChatRunning ? "Stop Chat" : "Start Chat" }}
				</button>
				<button class="youtube-page__button youtube-page__button--secondary" type="button" :disabled="busy" @click="discover">
					Discover Live
				</button>
				<button class="youtube-page__button" type="button" :disabled="busy" @click="simulate">Simulate Chat</button>
			</div>
		</header>

		<section class="youtube-page__panel youtube-page__settings">
			<div class="youtube-page__setting-header">
				<div>
					<h2>OAuth</h2>
					<p class="youtube-page__muted">
						{{
							hasBundledClientId
								? "ShowRunner includes YouTube OAuth credentials for one-click login."
								: "Add a Google OAuth desktop client ID before connecting."
						}}
					</p>
				</div>
				<button
					v-if="hasBundledClientId"
					class="youtube-page__button youtube-page__button--secondary"
					type="button"
					@click="showAdvanced = !showAdvanced"
				>
					{{ showAdvanced ? "Hide Advanced" : "Advanced" }}
				</button>
			</div>
			<p v-if="hasBundledCredentials && !showAdvanced" class="youtube-page__source">
				Using bundled ShowRunner OAuth client.
			</p>
			<label v-if="!hasBundledClientId || showAdvanced">
				<span>{{ hasBundledClientId ? "Override OAuth Client ID" : "Google OAuth Client ID" }}</span>
				<input v-model="clientId" type="text" placeholder="Desktop OAuth client ID" @change="saveSettings" />
			</label>
			<label v-if="!hasBundledClientSecret || showAdvanced">
				<span>{{ hasBundledClientSecret ? "Override OAuth Client Secret" : "Google OAuth Client Secret" }}</span>
				<input v-model="clientSecret" type="password" placeholder="Desktop OAuth client secret" @change="saveSettings" />
			</label>
			<label class="youtube-page__checkbox">
				<span>Start live chat ingest after login</span>
				<input v-model="autoStartLiveChat" type="checkbox" @change="saveSettings" />
			</label>
			<p class="youtube-page__muted">
				Google Desktop OAuth clients can require the generated client secret during token exchange.
			</p>
			<div class="youtube-page__checklist">
				<div v-for="item in checklist" :key="item.label" :class="['youtube-page__check', item.state]">
					<i :class="item.icon" />
					<div>
						<strong>{{ item.label }}</strong>
						<span>{{ item.detail }}</span>
					</div>
				</div>
			</div>
			<p v-if="statusHint" class="youtube-page__hint">{{ statusHint }}</p>
		</section>

		<section class="youtube-page__grid">
			<div class="youtube-page__panel">
				<h2>Connection</h2>
				<dl>
					<div>
						<dt>Status</dt>
						<dd>{{ status.connection?.status ?? "unknown" }}</dd>
					</div>
					<div>
						<dt>Account</dt>
						<dd>{{ status.connection?.accountName || "Not connected" }}</dd>
					</div>
					<div>
						<dt>Channel</dt>
						<dd>{{ status.connection?.channelId || "None" }}</dd>
					</div>
				</dl>
			</div>

			<div class="youtube-page__panel">
				<h2>Broadcast</h2>
				<p v-if="manualDiscoverySuggestion" class="youtube-page__hint">
					{{ manualDiscoverySuggestion }}
				</p>
				<dl>
					<div>
						<dt>Status</dt>
						<dd>{{ status.broadcast?.status ?? "unknown" }}</dd>
					</div>
					<div>
						<dt>Title</dt>
						<dd>{{ status.broadcast?.title || "No active broadcast" }}</dd>
					</div>
					<div>
						<dt>Live Chat</dt>
						<dd>{{ status.broadcast?.liveChatId || "Not discovered" }}</dd>
					</div>
					<div>
						<dt>Ingest</dt>
						<dd>{{ status.liveChatRunning ? "Running" : "Stopped" }}</dd>
					</div>
				</dl>
			</div>

			<div class="youtube-page__panel">
				<h2>API Diagnostics</h2>
				<dl>
					<div>
						<dt>Estimated Quota</dt>
						<dd>{{ status.diagnostics?.estimatedQuotaUnits ?? 0 }} units</dd>
					</div>
					<div>
						<dt>Search Discovery</dt>
						<dd>{{ discoveryStatus }}</dd>
					</div>
					<div>
						<dt>Live Chat Polls</dt>
						<dd>{{ status.diagnostics?.liveChatPolls ?? 0 }}</dd>
					</div>
					<div v-if="status.diagnostics?.nextRetryAt">
						<dt>Next Retry</dt>
						<dd>{{ formatTime(status.diagnostics.nextRetryAt) }}</dd>
					</div>
					<div v-if="status.diagnostics?.lastApiError">
						<dt>Last Error</dt>
						<dd>{{ status.diagnostics.lastApiError }}</dd>
					</div>
				</dl>
			</div>
		</section>

		<section class="youtube-page__panel youtube-page__manual">
			<div class="youtube-page__setting-header">
				<div>
					<h2>Manual Live Chat</h2>
					<p class="youtube-page__muted">
						Use this when auto-discovery cannot see your stream yet. Live Chat ID is enough to start ingest.
					</p>
				</div>
				<button class="youtube-page__button youtube-page__button--secondary" type="button" :disabled="busy" @click="applyManualBroadcast">
					Use Manual IDs
				</button>
			</div>
			<div class="youtube-page__manual-grid">
				<label>
					<span>Broadcast ID</span>
					<input v-model="manualBroadcastId" type="text" placeholder="Optional video/broadcast ID" />
				</label>
				<label>
					<span>Live Chat ID</span>
					<input v-model="manualLiveChatId" type="text" placeholder="Required for chat ingest" />
				</label>
			</div>
		</section>

		<section class="youtube-page__panel">
			<h2>Latest Message</h2>
			<p v-if="!status.latestMessage?.message" class="youtube-page__muted">No YouTube chat messages yet.</p>
			<div v-else class="youtube-page__message">
				<strong>{{ status.latestMessage.author }}</strong>
				<span>{{ status.latestMessage.message }}</span>
			</div>
		</section>

		<section class="youtube-page__panel">
			<h2>Activity Log</h2>
			<p v-if="!activityLog.length" class="youtube-page__muted">No activity yet.</p>
			<ul v-else class="youtube-page__activity">
				<li v-for="entry in activityLog" :key="entry.id" :class="`youtube-page__activity-item ${entry.severity}`">
					<strong>{{ entry.summary }}</strong>
					<span>{{ entry.detail }}</span>
				</li>
			</ul>
		</section>
	</div>
</template>

<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from "vue"
import { useIpcCaller } from "showrunner-ui-core"
import { useToast } from "primevue/usetoast"

interface YouTubeStatus {
	connection?: {
		accountName?: string
		channelId?: string
		status: string
		statusMessage?: string
	}
	broadcast?: {
		id?: string
		title?: string
		status: string
		liveChatId?: string
	}
	latestMessage?: {
		id?: string
		author?: string
		message?: string
		receivedAt?: string
	}
	settings?: {
		clientId?: string
		scopes?: string[]
		hasBundledClientId?: boolean
		hasBundledClientSecret?: boolean
		clientSecretConfigured?: boolean
		clientIdSource?: "bundled" | "manual" | "missing"
		autoStartLiveChat?: boolean
	}
	liveChatRunning?: boolean
	diagnostics?: {
		searchDiscoveryCooldownUntil?: string
		searchDiscoveryCached: boolean
		searchDiscoveryInFlight: boolean
		estimatedQuotaUnits: number
		liveChatPolls: number
		searchDiscoveries: number
		lastApiError?: string
		lastApiErrorAt?: string
		nextRetryAt?: string
	}
}

const getStatus = useIpcCaller<() => Promise<YouTubeStatus>>("youtube", "getStatus")
const saveYouTubeSettings = useIpcCaller<(settings: { clientId: string; clientSecret: string; autoStartLiveChat: boolean }) => Promise<unknown>>(
	"youtube",
	"saveSettings"
)
const connectYouTube = useIpcCaller<() => Promise<unknown>>("youtube", "connect")
const discoverBroadcast = useIpcCaller<() => Promise<unknown>>("youtube", "discoverBroadcast")
const setManualBroadcast = useIpcCaller<(manual: { broadcastId: string; liveChatId: string }) => Promise<unknown>>("youtube", "setManualBroadcast")
const startLiveChat = useIpcCaller<() => Promise<unknown>>("youtube", "startLiveChat")
const stopLiveChat = useIpcCaller<() => Promise<unknown>>("youtube", "stopLiveChat")
const simulateChatMessage = useIpcCaller<() => Promise<unknown>>("youtube", "simulateChatMessage")
const status = ref<YouTubeStatus>({})
const clientId = ref("")
const clientSecret = ref("")
const autoStartLiveChat = ref(false)
const manualBroadcastId = ref("")
const manualLiveChatId = ref("")
const showAdvanced = ref(false)
const toast = useToast()
const busy = ref(false)
const activityLog = ref<{ id: string; severity: "success" | "info" | "warn" | "error"; summary: string; detail: string }[]>([])
const lastSeenApiErrorAt = ref("")
let refreshTimer: ReturnType<typeof window.setInterval> | undefined

const hasBundledClientId = computed(() => Boolean(status.value.settings?.hasBundledClientId))
const hasBundledClientSecret = computed(() => Boolean(status.value.settings?.hasBundledClientSecret))
const hasBundledCredentials = computed(() => hasBundledClientId.value && hasBundledClientSecret.value)
const hasEffectiveClientId = computed(() => hasBundledClientId.value || Boolean(clientId.value.trim()))
const isConnected = computed(() => status.value.connection?.status === "connected")
const hasActiveBroadcast = computed(() => status.value.broadcast?.status === "live" && Boolean(status.value.broadcast?.liveChatId))
const discoveryStatus = computed(() => {
	const diagnostics = status.value.diagnostics
	if (!diagnostics) return "No discovery yet"
	if (diagnostics.searchDiscoveryInFlight) return "Searching now"
	if (diagnostics.searchDiscoveryCached && diagnostics.searchDiscoveryCooldownUntil) {
		return `Cooldown until ${formatTime(diagnostics.searchDiscoveryCooldownUntil)}`
	}
	return `${diagnostics.searchDiscoveries} search fallback${diagnostics.searchDiscoveries === 1 ? "" : "s"}`
})
const checklist = computed(() => [
	{
		label: "OAuth Client",
		detail: hasEffectiveClientId.value ? "Client ID is available." : "Add a Desktop OAuth client ID.",
		state: hasEffectiveClientId.value ? "ok" : "warn",
		icon: hasEffectiveClientId.value ? "mdi mdi-check-circle" : "mdi mdi-alert-circle",
	},
	{
		label: "Google Login",
		detail: isConnected.value ? `Connected as ${status.value.connection?.accountName}.` : "Use Connect to sign in with Google.",
		state: isConnected.value ? "ok" : "idle",
		icon: isConnected.value ? "mdi mdi-check-circle" : "mdi mdi-login",
	},
	{
		label: "Live Broadcast",
		detail: hasActiveBroadcast.value ? "Active live chat discovered." : "Start ingest when your YouTube broadcast is live.",
		state: hasActiveBroadcast.value ? "ok" : "idle",
		icon: hasActiveBroadcast.value ? "mdi mdi-check-circle" : "mdi mdi-broadcast",
	},
])
const statusHint = computed(() => {
	const message = status.value.connection?.statusMessage || ""
	if (/quota|rate|limit/i.test(message)) return "YouTube API quota/rate limit was hit. Wait for quota reset or reduce polling frequency."
	if (/client_secret/i.test(message)) return "Your Google OAuth client likely requires the generated Desktop client secret."
	if (/access_denied|verification/i.test(message)) return "Your Google app is still in testing. Add your Google account as a test user in OAuth consent screen."
	if (/No active YouTube broadcast|live chat was found|live chat is not available/i.test(message)) return "Auto-discovery did not find an ingestable chat. Paste a Broadcast ID or Live Chat ID in Manual Live Chat."
	return message && status.value.connection?.status === "error" ? message : ""
})
const manualDiscoverySuggestion = computed(() => {
	if (hasActiveBroadcast.value) return ""
	const message = status.value.connection?.statusMessage || ""
	if (/No active YouTube broadcast|not available|not found/i.test(message)) {
		return "Auto-discovery could not find a usable live chat. Use Manual Live Chat below with the stream Broadcast ID or Live Chat ID."
	}
	return ""
})

async function refresh() {
	const nextStatus = await getStatus()
	status.value = nextStatus
	clientId.value = status.value.settings?.clientId ?? ""
	autoStartLiveChat.value = Boolean(status.value.settings?.autoStartLiveChat)
	manualBroadcastId.value = status.value.broadcast?.id ?? manualBroadcastId.value
	manualLiveChatId.value = status.value.broadcast?.liveChatId ?? manualLiveChatId.value
	const apiErrorAt = status.value.diagnostics?.lastApiErrorAt
	if (apiErrorAt && apiErrorAt !== lastSeenApiErrorAt.value && status.value.diagnostics?.lastApiError) {
		lastSeenApiErrorAt.value = apiErrorAt
		addActivity("error", "YouTube API error", status.value.diagnostics.lastApiError)
		toast.add({ severity: "error", summary: "YouTube API error", detail: status.value.diagnostics.lastApiError, life: 6000 })
	}
}

async function saveSettings() {
	await runWithFeedback("success", "YouTube settings saved.", async () => {
		await saveYouTubeSettings({
			clientId: clientId.value,
			clientSecret: clientSecret.value,
			autoStartLiveChat: autoStartLiveChat.value,
		})
		await refresh()
	})
}

async function connect() {
	await runWithFeedback("success", "Connected to YouTube.", async () => {
		if (!hasBundledCredentials.value || showAdvanced.value) {
			await saveYouTubeSettings({
				clientId: clientId.value,
				clientSecret: clientSecret.value,
				autoStartLiveChat: autoStartLiveChat.value,
			})
		}
		await connectYouTube()
		if (autoStartLiveChat.value) {
			await startLiveChat()
		}
		await refresh()
	})
}

async function toggleLiveChat() {
	await runWithFeedback("success", status.value.liveChatRunning ? "YouTube chat ingest stopped." : "YouTube chat ingest started.", async () => {
		if (status.value.liveChatRunning) {
			await stopLiveChat()
		} else {
			await startLiveChat()
		}
		await refresh()
	})
}

async function discover() {
	await runWithFeedback("info", "YouTube broadcast discovery finished.", async () => {
		await discoverBroadcast()
		await refresh()
	})
	if (!hasActiveBroadcast.value) {
		addActivity("warn", "No active YouTube live chat found.", "Use Manual Live Chat with a Broadcast ID or Live Chat ID.")
		toast.add({ severity: "warn", summary: "No active YouTube chat", detail: "Try Manual Live Chat IDs below.", life: 5000 })
	}
}

async function applyManualBroadcast() {
	await runWithFeedback("success", "Manual YouTube live chat saved.", async () => {
		await setManualBroadcast({
			broadcastId: manualBroadcastId.value,
			liveChatId: manualLiveChatId.value,
		})
		await refresh()
	})
}

async function simulate() {
	await runWithFeedback("success", "Simulated YouTube chat message.", async () => {
		await simulateChatMessage()
		await refresh()
	})
}

async function runWithFeedback(severity: "success" | "info", successMessage: string, action: () => Promise<void>) {
	busy.value = true
	try {
		await action()
		addActivity(severity, successMessage)
		toast.add({ severity, summary: successMessage, life: 2500 })
	} catch (error) {
		const detail = error instanceof Error ? error.message : String(error)
		addActivity("error", "YouTube action failed.", detail)
		toast.add({ severity: "error", summary: "YouTube action failed", detail, life: 6000 })
		throw error
	} finally {
		busy.value = false
	}
}

function addActivity(severity: "success" | "info" | "warn" | "error", summary: string, detail = new Date().toLocaleTimeString()) {
	activityLog.value.unshift({
		id: `${Date.now()}-${Math.random()}`,
		severity,
		summary,
		detail,
	})
	activityLog.value = activityLog.value.slice(0, 12)
}

function formatTime(value: string) {
	const date = new Date(value)
	if (!Number.isFinite(date.getTime())) return value
	return date.toLocaleTimeString()
}

onMounted(() => {
	void refresh()
	refreshTimer = window.setInterval(() => void refresh(), 5000)
})

onBeforeUnmount(() => {
	if (refreshTimer) window.clearInterval(refreshTimer)
})
</script>

<style scoped>
.youtube-page {
	display: flex;
	flex-direction: column;
	gap: 1rem;
	padding: 1rem;
}

.youtube-page__header {
	align-items: center;
	display: flex;
	justify-content: space-between;
}

.youtube-page__eyebrow {
	color: var(--text-color-secondary);
	font-size: 0.8rem;
	margin: 0 0 0.25rem;
	text-transform: uppercase;
}

.youtube-page h1,
.youtube-page h2 {
	margin: 0;
}

.youtube-page__grid {
	display: grid;
	gap: 1rem;
	grid-template-columns: repeat(auto-fit, minmax(16rem, 1fr));
}

.youtube-page__panel {
	background: var(--surface-900);
	border: 1px solid var(--surface-700);
	border-radius: 6px;
	padding: 1rem;
}

.youtube-page__panel dl {
	display: grid;
	gap: 0.75rem;
	margin: 1rem 0 0;
}

.youtube-page__panel dl div {
	display: flex;
	justify-content: space-between;
	gap: 1rem;
}

.youtube-page__panel dt,
.youtube-page__muted {
	color: var(--text-color-secondary);
}

.youtube-page__panel dd {
	margin: 0;
	text-align: right;
}

.youtube-page__button {
	background: #ff0033;
	border: 0;
	border-radius: 4px;
	color: white;
	cursor: pointer;
	font-weight: 700;
	padding: 0.65rem 0.9rem;
}

.youtube-page__button--secondary {
	background: var(--surface-700);
}

.youtube-page__actions {
	display: flex;
	gap: 0.5rem;
}

.youtube-page__settings {
	display: grid;
	gap: 0.75rem;
}

.youtube-page__setting-header {
	align-items: start;
	display: flex;
	gap: 1rem;
	justify-content: space-between;
}

.youtube-page__settings label,
.youtube-page__manual label {
	display: grid;
	gap: 0.4rem;
}

.youtube-page__settings label.youtube-page__checkbox {
	align-items: center;
	display: flex;
	justify-content: space-between;
}

.youtube-page__settings input,
.youtube-page__manual input {
	background: var(--surface-950);
	border: 1px solid var(--surface-700);
	border-radius: 4px;
	color: var(--text-color);
	padding: 0.6rem 0.7rem;
}

.youtube-page__manual {
	display: grid;
	gap: 0.8rem;
}

.youtube-page__manual-grid {
	display: grid;
	gap: 0.75rem;
	grid-template-columns: repeat(auto-fit, minmax(18rem, 1fr));
}

.youtube-page__source {
	background: color-mix(in srgb, #ff0033 14%, transparent);
	border: 1px solid color-mix(in srgb, #ff0033 45%, transparent);
	border-radius: 4px;
	margin: 0;
	padding: 0.65rem 0.75rem;
}

.youtube-page__message {
	display: flex;
	gap: 0.75rem;
	margin-top: 1rem;
}

.youtube-page__checklist {
	display: grid;
	gap: 0.55rem;
}

.youtube-page__check {
	align-items: center;
	background: var(--surface-950);
	border: 1px solid var(--surface-700);
	border-radius: 6px;
	display: grid;
	gap: 0.65rem;
	grid-template-columns: 1.75rem 1fr;
	padding: 0.65rem 0.75rem;
}

.youtube-page__check i {
	font-size: 1.25rem;
}

.youtube-page__check strong,
.youtube-page__check span {
	display: block;
}

.youtube-page__check span {
	color: var(--text-color-secondary);
	font-size: 0.86rem;
}

.youtube-page__check.ok i {
	color: #2ed47a;
}

.youtube-page__check.warn i,
.youtube-page__hint {
	color: #ffc857;
}

.youtube-page__hint {
	background: color-mix(in srgb, #ffc857 10%, transparent);
	border: 1px solid color-mix(in srgb, #ffc857 35%, transparent);
	border-radius: 4px;
	margin: 0;
	padding: 0.65rem 0.75rem;
}

.youtube-page__activity {
	display: grid;
	gap: 0.5rem;
	list-style: none;
	margin: 0;
	padding: 0;
}

.youtube-page__activity-item {
	background: var(--surface-950);
	border-left: 3px solid var(--surface-500);
	border-radius: 4px;
	display: grid;
	gap: 0.2rem;
	padding: 0.55rem 0.65rem;
}

.youtube-page__activity-item.success {
	border-left-color: #20d6b5;
}

.youtube-page__activity-item.error {
	border-left-color: #ff5c7a;
}

.youtube-page__activity-item.info {
	border-left-color: #8ab4ff;
}

.youtube-page__activity-item span {
	color: var(--text-color-secondary);
	font-size: 0.85rem;
	overflow-wrap: anywhere;
}
</style>
