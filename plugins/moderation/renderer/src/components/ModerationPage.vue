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
				<button class="moderation-page__button" type="button" @click="save">Save</button>
			</div>
		</header>

		<section class="moderation-page__panel">
			<h2>Connection</h2>
			<label>
				<span>Enable moderation docker</span>
				<input v-model="draft.enabled" type="checkbox" />
			</label>
			<label>
				<span>API URL</span>
				<input v-model="draft.apiBaseUrl" type="text" />
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
	</div>
</template>

<script setup lang="ts">
import { onMounted, reactive, ref } from "vue"
import { useIpcCaller } from "castmate-ui-core"
import { ModerationSettings, ModerationStatus } from "castmate-plugin-moderation-shared"

const getStatus = useIpcCaller<() => Promise<ModerationStatus>>("moderation", "getStatus")
const saveSettings = useIpcCaller<(settings: Partial<ModerationSettings>) => Promise<ModerationStatus>>(
	"moderation",
	"saveSettings"
)
const runHealthCheck = useIpcCaller<() => Promise<ModerationStatus>>("moderation", "checkHealth")
const status = ref<Partial<ModerationStatus>>({})
const draft = reactive<ModerationSettings>({
	enabled: false,
	apiBaseUrl: "http://localhost:8787",
	dashboardWsUrl: "ws://localhost:8787/ws?channel=dashboard",
	forwardYouTube: true,
})

async function refresh() {
	applyStatus(await getStatus())
}

async function save() {
	applyStatus(await saveSettings({ ...draft }))
}

async function checkHealth() {
	applyStatus(await runHealthCheck())
}

function applyStatus(nextStatus: ModerationStatus) {
	status.value = nextStatus
	draft.enabled = nextStatus.enabled
	draft.apiBaseUrl = nextStatus.apiBaseUrl
	draft.dashboardWsUrl = nextStatus.dashboardWsUrl
	draft.forwardYouTube = nextStatus.forwardYouTube
}

onMounted(refresh)
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
.moderation-page h2 {
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

.moderation-page__button--ghost {
	background: var(--surface-700);
	color: var(--text-color);
}
</style>
