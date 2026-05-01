<template>
	<div class="youtube-page">
		<header class="youtube-page__header">
			<div>
				<p class="youtube-page__eyebrow">Platform Integration</p>
				<h1>YouTube Live</h1>
			</div>
			<div class="youtube-page__actions">
				<button class="youtube-page__button youtube-page__button--secondary" type="button" @click="connect">
					Connect
				</button>
				<button class="youtube-page__button youtube-page__button--secondary" type="button" @click="toggleLiveChat">
					{{ status.liveChatRunning ? "Stop Chat" : "Start Chat" }}
				</button>
				<button class="youtube-page__button" type="button" @click="simulate">Simulate Chat</button>
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
			<p class="youtube-page__muted">
				Google Desktop OAuth clients can require the generated client secret during token exchange.
			</p>
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
		</section>

		<section class="youtube-page__panel">
			<h2>Latest Message</h2>
			<p v-if="!status.latestMessage?.message" class="youtube-page__muted">No YouTube chat messages yet.</p>
			<div v-else class="youtube-page__message">
				<strong>{{ status.latestMessage.author }}</strong>
				<span>{{ status.latestMessage.message }}</span>
			</div>
		</section>
	</div>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from "vue"
import { useIpcCaller } from "castmate-ui-core"

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
	}
	liveChatRunning?: boolean
}

const getStatus = useIpcCaller<() => Promise<YouTubeStatus>>("youtube", "getStatus")
const saveYouTubeSettings = useIpcCaller<(settings: { clientId: string; clientSecret: string }) => Promise<unknown>>("youtube", "saveSettings")
const connectYouTube = useIpcCaller<() => Promise<unknown>>("youtube", "connect")
const startLiveChat = useIpcCaller<() => Promise<unknown>>("youtube", "startLiveChat")
const stopLiveChat = useIpcCaller<() => Promise<unknown>>("youtube", "stopLiveChat")
const simulateChatMessage = useIpcCaller<() => Promise<unknown>>("youtube", "simulateChatMessage")
const status = ref<YouTubeStatus>({})
const clientId = ref("")
const clientSecret = ref("")
const showAdvanced = ref(false)

const hasBundledClientId = computed(() => Boolean(status.value.settings?.hasBundledClientId))
const hasBundledClientSecret = computed(() => Boolean(status.value.settings?.hasBundledClientSecret))
const hasBundledCredentials = computed(() => hasBundledClientId.value && hasBundledClientSecret.value)

async function refresh() {
	status.value = await getStatus()
	clientId.value = status.value.settings?.clientId ?? ""
}

async function saveSettings() {
	await saveYouTubeSettings({ clientId: clientId.value, clientSecret: clientSecret.value })
	await refresh()
}

async function connect() {
	if (!hasBundledCredentials.value || showAdvanced.value) {
		await saveSettings()
	}
	await connectYouTube()
	await refresh()
}

async function toggleLiveChat() {
	if (status.value.liveChatRunning) {
		await stopLiveChat()
	} else {
		await startLiveChat()
	}
	await refresh()
}

async function simulate() {
	await simulateChatMessage()
	await refresh()
}

onMounted(refresh)
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

.youtube-page__settings label {
	display: grid;
	gap: 0.4rem;
}

.youtube-page__settings input {
	background: var(--surface-950);
	border: 1px solid var(--surface-700);
	border-radius: 4px;
	color: var(--text-color);
	padding: 0.6rem 0.7rem;
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
</style>
