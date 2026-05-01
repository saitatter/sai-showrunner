<template>
	<div>
		<h1 class="text-center mb-0">
			<i class="mdi mdi-youtube youtube-red"></i>Setup YouTube <migration-check-box :checked="ready" />
		</h1>
		<p class="m-0 mb-4 text-center p-text-secondary">
			Connect a YouTube channel to enable live chat, Super Chat, and membership triggers.
		</p>

		<div class="flex flex-column align-items-center gap-3">
			<div class="youtube-setup-card">
				<div v-if="hasBundledClientId" class="youtube-setup-card__source">
					ShowRunner includes a YouTube OAuth client. Connect with your browser to continue.
				</div>
				<label v-else class="flex flex-column gap-2">
					<span>Google OAuth Client ID</span>
					<input v-model="clientId" type="text" placeholder="Desktop OAuth client ID" @change="saveSettings" />
				</label>
				<p class="p-text-secondary text-sm m-0">
					{{ hasBundledClientId ? "No client secret is stored in the app." : "Use a Google OAuth desktop client with the YouTube Data API enabled." }}
				</p>
				<div class="flex flex-row justify-content-center gap-2">
					<p-button @click="connect" :loading="connecting">Connect YouTube</p-button>
					<p-button outlined @click="refresh">Refresh</p-button>
				</div>
			</div>

			<div class="text-center">
				<div>
					Status:
					<strong>{{ status.connection?.status ?? "disconnected" }}</strong>
				</div>
				<div v-if="status.connection?.accountName" class="p-text-secondary">
					{{ status.connection.accountName }}
				</div>
				<div v-if="status.connection?.statusMessage" class="p-text-secondary text-sm">
					{{ status.connection.statusMessage }}
				</div>
			</div>
		</div>
	</div>
</template>

<script setup lang="ts">
import { useIpcCaller } from "castmate-ui-core"
import PButton from "primevue/button"
import { computed, onMounted, ref, useModel, watch } from "vue"
import MigrationCheckBox from "../migration/MigrationCheckBox.vue"

interface YouTubeStatus {
	connection?: {
		accountName?: string
		channelId?: string
		status: string
		statusMessage?: string
	}
	settings?: {
		clientId?: string
		scopes?: string[]
		hasBundledClientId?: boolean
		clientIdSource?: "bundled" | "manual" | "missing"
	}
}

const props = defineProps<{
	ready: boolean
}>()

const ready = useModel(props, "ready")
const getStatus = useIpcCaller<() => Promise<YouTubeStatus>>("youtube", "getStatus")
const saveYouTubeSettings = useIpcCaller<(settings: { clientId: string }) => Promise<unknown>>("youtube", "saveSettings")
const connectYouTube = useIpcCaller<() => Promise<unknown>>("youtube", "connect")

const status = ref<YouTubeStatus>({})
const clientId = ref("")
const connecting = ref(false)

const readyComputed = computed(() => status.value.connection?.status === "connected")
const hasBundledClientId = computed(() => Boolean(status.value.settings?.hasBundledClientId))

async function refresh() {
	status.value = await getStatus()
	clientId.value = status.value.settings?.clientId ?? ""
}

async function saveSettings() {
	await saveYouTubeSettings({ clientId: clientId.value })
	await refresh()
}

async function connect() {
	connecting.value = true
	try {
		if (!hasBundledClientId.value) {
			await saveSettings()
		}
		await connectYouTube()
		await refresh()
	} finally {
		connecting.value = false
	}
}

onMounted(async () => {
	await refresh()
	watch(
		readyComputed,
		() => {
			ready.value = readyComputed.value
		},
		{ immediate: true }
	)
})
</script>

<style scoped>
.youtube-setup-card {
	background: var(--surface-900);
	border: 1px solid var(--surface-700);
	border-radius: 6px;
	display: flex;
	flex-direction: column;
	gap: 1rem;
	max-width: 34rem;
	padding: 1rem;
	width: 100%;
}

.youtube-setup-card input {
	background: var(--surface-950);
	border: 1px solid var(--surface-700);
	border-radius: 4px;
	color: var(--text-color);
	padding: 0.65rem 0.75rem;
}

.youtube-setup-card__source {
	background: color-mix(in srgb, #ff0033 14%, transparent);
	border: 1px solid color-mix(in srgb, #ff0033 45%, transparent);
	border-radius: 4px;
	padding: 0.75rem;
}
</style>
