<template>
	<div class="moderation-page">
		<header class="moderation-page__header">
			<div>
				<p class="moderation-page__eyebrow">Integration</p>
				<h1>Moderation Docker</h1>
			</div>
			<div class="moderation-page__actions">
				<button class="moderation-page__button moderation-page__button--ghost" type="button" @click="checkHealth">
					Health
				</button>
				<button class="moderation-page__button moderation-page__button--ghost" type="button" @click="sendTest">
					Send Test Event
				</button>
				<button class="moderation-page__button" type="button" @click="save">Save</button>
			</div>
		</header>

		<section class="moderation-page__panel">
			<h2>Connection</h2>
			<div class="moderation-page__presets">
				<button type="button" @click="applyPreset('local')">Localhost</button>
				<button type="button" @click="applyPreset('dockerHost')">Docker Host</button>
			</div>
			<label>
				<span>Enable moderation docker</span>
				<input v-model="draft.enabled" type="checkbox" />
			</label>
			<label>
				<span>API URL</span>
				<input v-model="draft.apiBaseUrl" type="text" />
			</label>
			<label>
				<span>API Token</span>
				<input v-model="draft.apiToken" autocomplete="off" type="password" />
			</label>
			<label>
				<span>Dashboard WebSocket URL</span>
				<input v-model="draft.dashboardWsUrl" type="text" />
			</label>
			<label>
				<span>Forward YouTube chat</span>
				<input v-model="draft.forwardYouTube" type="checkbox" />
			</label>
		</section>

		<section class="moderation-page__panel">
			<h2>Status</h2>
			<dl>
				<div>
					<dt>Health</dt>
					<dd>{{ status.health ?? "unknown" }}</dd>
				</div>
				<div>
					<dt>WebSocket</dt>
					<dd>{{ status.connected ? "Connected" : "Disconnected" }}</dd>
				</div>
				<div>
					<dt>Processed</dt>
					<dd>{{ status.processedMessages ?? 0 }}</dd>
				</div>
				<div>
					<dt>Approved</dt>
					<dd>{{ status.approvedMessages ?? 0 }}</dd>
				</div>
				<div>
					<dt>Blocked</dt>
					<dd>{{ status.blockedMessages ?? 0 }}</dd>
				</div>
				<div>
					<dt>Flagged</dt>
					<dd>{{ status.flaggedMessages ?? 0 }}</dd>
				</div>
				<div>
					<dt>Last Decision</dt>
					<dd>{{ status.lastDecision ?? "none" }}</dd>
				</div>
				<div>
					<dt>Message</dt>
					<dd>{{ status.statusMessage ?? "No status yet." }}</dd>
				</div>
			</dl>
		</section>

		<section class="moderation-page__panel moderation-page__panel--queue">
			<div class="moderation-page__section-header">
				<h2>Moderation Queue</h2>
				<button class="moderation-page__button moderation-page__button--ghost" type="button" @click="refreshQueue">
					Refresh Queue
				</button>
			</div>
			<div class="moderation-page__queues">
				<div v-for="queueConfig in queueConfigs" :key="queueConfig.key" class="moderation-page__queue">
					<h3>{{ queueConfig.label }}</h3>
					<p v-if="!queue[queueConfig.key]?.length" class="moderation-page__muted">No messages.</p>
					<ul v-else class="moderation-page__feed moderation-page__feed--queue">
						<li v-for="entry in queue[queueConfig.key]" :key="`${queueConfig.key}:${entry.messageId}:${entry.verdict}`">
							<div>
								<strong>{{ entry.username || "unknown" }}</strong>
								<span>{{ entry.platform }} · {{ entry.verdict }}</span>
								<small>{{ entry.messageId }}</small>
							</div>
							<p>{{ entry.text }}</p>
							<div class="moderation-page__queue-actions">
								<button type="button" @click="override(entry.messageId, 'approve')">Approve</button>
								<button type="button" @click="override(entry.messageId, 'block')">Block</button>
								<button type="button" @click="override(entry.messageId, 'falsePositive')">False Positive</button>
							</div>
						</li>
					</ul>
				</div>
			</div>
		</section>

		<section class="moderation-page__panel">
			<h2>Latest Decisions</h2>
			<p v-if="!status.recentDecisions?.length" class="moderation-page__muted">No moderation dashboard events yet.</p>
			<ul v-else class="moderation-page__feed">
				<li v-for="decision in status.recentDecisions" :key="`${decision.messageId || decision.receivedAt}:${decision.decision}`">
					<strong>{{ decision.decision }}</strong>
					<span>{{ decision.eventType }}</span>
					<small>{{ decision.messageId || decision.receivedAt }}</small>
				</li>
			</ul>
		</section>
	</div>
</template>

<script setup lang="ts">
import { onBeforeUnmount, onMounted, reactive, ref } from "vue"
import { useIpcCaller } from "castmate-ui-core"
import {
	ModerationOverrideRequest,
	ModerationQueueState,
	ModerationSettings,
	ModerationStatus,
} from "castmate-plugin-moderation-shared"

const getStatus = useIpcCaller<() => Promise<ModerationStatus>>("moderation", "getStatus")
const saveSettings = useIpcCaller<(settings: Partial<ModerationSettings>) => Promise<ModerationStatus>>(
	"moderation",
	"saveSettings"
)
const runHealthCheck = useIpcCaller<() => Promise<ModerationStatus>>("moderation", "checkHealth")
const sendTestMessage = useIpcCaller<() => Promise<ModerationStatus>>("moderation", "sendTestMessage")
const getQueue = useIpcCaller<() => Promise<ModerationQueueState>>("moderation", "getQueue")
const requestOverride = useIpcCaller<(request: ModerationOverrideRequest) => Promise<ModerationQueueState>>(
	"moderation",
	"requestOverride"
)
const status = ref<Partial<ModerationStatus>>({})
const queue = ref<ModerationQueueState>({
	latest: [],
	pending: [],
	approved: [],
	rejected: [],
})
const draft = reactive<ModerationSettings>({
	enabled: false,
	apiBaseUrl: "http://localhost:8787",
	apiToken: "",
	dashboardWsUrl: "ws://localhost:8787/ws?channel=dashboard",
	forwardYouTube: true,
})

const presets = {
	local: {
		apiBaseUrl: "http://localhost:8787",
		dashboardWsUrl: "ws://localhost:8787/ws?channel=dashboard",
	},
	dockerHost: {
		apiBaseUrl: "http://host.docker.internal:8787",
		dashboardWsUrl: "ws://host.docker.internal:8787/ws?channel=dashboard",
	},
}
const queueConfigs: { key: keyof ModerationQueueState; label: string }[] = [
	{ key: "pending", label: "Pending" },
	{ key: "approved", label: "Approved" },
	{ key: "rejected", label: "Rejected" },
	{ key: "latest", label: "Latest" },
]
let refreshTimer: ReturnType<typeof setInterval> | undefined

async function refresh() {
	const [nextStatus, nextQueue] = await Promise.allSettled([getStatus(), getQueue()])
	if (nextStatus.status === "fulfilled") applyStatus(nextStatus.value)
	if (nextQueue.status === "fulfilled") queue.value = nextQueue.value
}

async function save() {
	applyStatus(await saveSettings({ ...draft }))
	await refreshQueue()
}

async function checkHealth() {
	applyStatus(await runHealthCheck())
	await refreshQueue()
}

function applyPreset(name: keyof typeof presets) {
	draft.apiBaseUrl = presets[name].apiBaseUrl
	draft.dashboardWsUrl = presets[name].dashboardWsUrl
}

async function sendTest() {
	applyStatus(await sendTestMessage())
	await refreshQueue()
}

async function refreshQueue() {
	queue.value = await getQueue()
}

async function override(messageId: string, action: ModerationOverrideRequest["action"]) {
	if (!messageId) return
	queue.value = await requestOverride({
		messageId,
		action,
		operatorId: "showrunner",
		reason: `ShowRunner ${action}`,
	})
	applyStatus(await getStatus())
}

function applyStatus(nextStatus: ModerationStatus) {
	status.value = nextStatus
	draft.enabled = nextStatus.enabled
	draft.apiBaseUrl = nextStatus.apiBaseUrl
	draft.apiToken = nextStatus.apiToken
	draft.dashboardWsUrl = nextStatus.dashboardWsUrl
	draft.forwardYouTube = nextStatus.forwardYouTube
}

onMounted(() => {
	void refresh()
	refreshTimer = setInterval(() => void refresh(), 5000)
})
onBeforeUnmount(() => {
	if (refreshTimer) clearInterval(refreshTimer)
})
</script>

<style scoped>
.moderation-page {
	display: flex;
	flex-direction: column;
	gap: 1rem;
	padding: 1rem;
}

.moderation-page__header {
	align-items: center;
	display: flex;
	gap: 1rem;
	justify-content: space-between;
}

.moderation-page__eyebrow {
	color: var(--text-color-secondary);
	font-size: 0.8rem;
	margin: 0 0 0.25rem;
	text-transform: uppercase;
}

.moderation-page h1,
.moderation-page h2,
.moderation-page h3 {
	margin: 0;
}

.moderation-page__panel {
	background: var(--surface-900);
	border: 1px solid var(--surface-700);
	border-radius: 6px;
	display: grid;
	gap: 0.85rem;
	padding: 1rem;
}

.moderation-page__panel label {
	align-items: center;
	display: grid;
	gap: 0.5rem;
	grid-template-columns: minmax(12rem, 14rem) 1fr;
}

.moderation-page__presets {
	display: flex;
	gap: 0.5rem;
}

.moderation-page__presets button {
	background: var(--surface-700);
	border: 1px solid var(--surface-600);
	border-radius: 4px;
	color: var(--text-color);
	cursor: pointer;
	padding: 0.45rem 0.65rem;
}

.moderation-page__panel input[type="password"],
.moderation-page__panel input[type="text"] {
	background: var(--surface-950);
	border: 1px solid var(--surface-700);
	border-radius: 4px;
	color: var(--text-color);
	padding: 0.55rem 0.65rem;
}

.moderation-page__panel dl {
	display: grid;
	gap: 0.75rem;
	margin: 1rem 0 0;
}

.moderation-page__panel dl div {
	display: flex;
	gap: 1rem;
	justify-content: space-between;
}

.moderation-page__panel dt {
	color: var(--text-color-secondary);
}

.moderation-page__muted {
	color: var(--text-color-secondary);
	margin: 0;
}

.moderation-page__panel dd {
	margin: 0;
	text-align: right;
}

.moderation-page__button {
	background: #20d6b5;
	border: 0;
	border-radius: 4px;
	color: #07110f;
	cursor: pointer;
	font-weight: 700;
	padding: 0.65rem 0.9rem;
}

.moderation-page__actions {
	display: flex;
	gap: 0.5rem;
}

.moderation-page__section-header {
	align-items: center;
	display: flex;
	justify-content: space-between;
}

.moderation-page__button--ghost {
	background: var(--surface-700);
	color: var(--text-color);
}

.moderation-page__queues {
	display: grid;
	gap: 1rem;
	grid-template-columns: repeat(auto-fit, minmax(18rem, 1fr));
}

.moderation-page__queue {
	background: var(--surface-950);
	border: 1px solid var(--surface-700);
	border-radius: 4px;
	display: grid;
	gap: 0.65rem;
	padding: 0.75rem;
}

.moderation-page__feed {
	display: grid;
	gap: 0.5rem;
	list-style: none;
	margin: 0;
	padding: 0;
}

.moderation-page__feed li {
	align-items: center;
	background: var(--surface-950);
	border: 1px solid var(--surface-700);
	border-radius: 4px;
	display: grid;
	gap: 0.5rem;
	grid-template-columns: 7rem 1fr minmax(8rem, auto);
	padding: 0.55rem 0.65rem;
}

.moderation-page__feed small {
	color: var(--text-color-secondary);
	overflow: hidden;
	text-align: right;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.moderation-page__feed--queue li {
	align-items: stretch;
	grid-template-columns: 1fr;
}

.moderation-page__feed--queue li p {
	color: var(--text-color);
	margin: 0;
	overflow-wrap: anywhere;
}

.moderation-page__feed--queue li span {
	color: var(--text-color-secondary);
	display: block;
}

.moderation-page__queue-actions {
	display: flex;
	flex-wrap: wrap;
	gap: 0.35rem;
}

.moderation-page__queue-actions button {
	background: var(--surface-700);
	border: 1px solid var(--surface-600);
	border-radius: 4px;
	color: var(--text-color);
	cursor: pointer;
	padding: 0.35rem 0.45rem;
}
</style>
