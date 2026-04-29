<template>
	<div class="youtube-page">
		<header class="youtube-page__header">
			<div>
				<p class="youtube-page__eyebrow">Platform Integration</p>
				<h1>YouTube Live</h1>
			</div>
			<button class="youtube-page__button" type="button" @click="simulate">Simulate Chat</button>
		</header>

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
import { onMounted, ref } from "vue"
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
}

const getStatus = useIpcCaller<() => Promise<YouTubeStatus>>("youtube", "getStatus")
const simulateChatMessage = useIpcCaller<() => Promise<unknown>>("youtube", "simulateChatMessage")
const status = ref<YouTubeStatus>({})

async function refresh() {
	status.value = await getStatus()
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

.youtube-page__message {
	display: flex;
	gap: 0.75rem;
	margin-top: 1rem;
}
</style>
