<template>
	<div class="moderation-page">
		<header class="moderation-page__header">
			<div>
				<p class="moderation-page__eyebrow">Integration</p>
				<h1>Moderation Docker</h1>
			</div>
			<button class="moderation-page__button" type="button" @click="refresh">Refresh</button>
		</header>

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
			</dl>
		</section>
	</div>
</template>

<script setup lang="ts">
import { onMounted, ref } from "vue"
import { useIpcCaller } from "castmate-ui-core"
import { ModerationStatus } from "castmate-plugin-moderation-shared"

const getStatus = useIpcCaller<() => Promise<ModerationStatus>>("moderation", "getStatus")
const status = ref<Partial<ModerationStatus>>({})

async function refresh() {
	status.value = await getStatus()
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
	padding: 1rem;
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
</style>
