<template>
	<scrolling-tab-body>
		<div class="updates-page">
			<div class="updates-page__header">
				<div>
					<h1>Updates</h1>
					<p>Current version: v{{ status?.currentVersion ?? "unknown" }}</p>
				</div>
				<div class="updates-page__actions">
					<p-button icon="mdi mdi-refresh" :disabled="!status?.canCheckForUpdates" :loading="checking" @click="checkNow">Check for updates</p-button>
					<p-button
						v-if="status?.hasUpdate"
						icon="mdi mdi-download"
						:loading="updating"
						@click="installUpdate"
					>
						Update and restart
					</p-button>
				</div>
			</div>

			<section class="updates-page__status" :class="statusClass">
				<div>
					<strong>{{ statusTitle }}</strong>
					<p>{{ statusDetail }}</p>
				</div>
				<div class="updates-page__meta">
					<span>Latest version</span>
					<strong>{{ latestVersionLabel }}</strong>
				</div>
			</section>

			<section class="updates-page__notes">
				<div class="updates-page__section-title">
					<h2>Release Notes</h2>
					<span v-if="checkedAtLabel">{{ checkedAtLabel }}</span>
				</div>
				<flex-scroller class="updates-page__notes-body" inner-class="updates-page__notes-inner">
					<div v-if="sanitizedReleaseNotes" ref="notes" class="updates-page__release-notes" v-html="sanitizedReleaseNotes"></div>
					<p v-else class="updates-page__empty">Release notes will appear here after checking for updates.</p>
				</flex-scroller>
			</section>
		</div>
	</scrolling-tab-body>
</template>

<script setup lang="ts">
import { UpdateStatus } from "showrunner-schema"
import { FlexScroller, ScrollingTabBody, useAppFeedback, useIpcCaller } from "showrunner-ui-core"
import { computed, nextTick, onMounted, ref, watch } from "vue"
import PButton from "primevue/button"
import { sanitizeReleaseNotes } from "../../util/sanitize-html"

const status = ref<UpdateStatus>()
const checking = ref(false)
const updating = ref(false)
const notes = ref<HTMLElement>()

const feedback = useAppFeedback("Updates")

const getUpdateStatus = useIpcCaller<() => UpdateStatus>("info", "getUpdateStatus")
const checkForUpdates = useIpcCaller<() => Promise<UpdateStatus>>("info", "checkForUpdates")
const updateShowRunner = useIpcCaller<() => Promise<void>>("info", "updateShowRunner")

const latestInfo = computed(() => status.value?.latest ?? status.value?.update)
const releaseNotes = computed(() => latestInfo.value?.notes?.trim() ?? "")
const sanitizedReleaseNotes = computed(() => sanitizeReleaseNotes(releaseNotes.value))

const latestVersionLabel = computed(() => {
	const latest = latestInfo.value?.version
	return latest ? `v${latest}` : "unknown"
})

const checkedAtLabel = computed(() => {
	if (!status.value?.checkedAt) return ""
	return `Last checked ${new Date(status.value.checkedAt).toLocaleString()}`
})

const statusClass = computed(() => {
	if (status.value?.error) return "updates-page__status--error"
	if (status.value && !status.value.canCheckForUpdates) return "updates-page__status--muted"
	if (status.value?.hasUpdate) return "updates-page__status--available"
	return "updates-page__status--current"
})

const statusTitle = computed(() => {
	if (status.value?.error) return "Update check failed"
	if (status.value && !status.value.canCheckForUpdates) return "Development build"
	if (status.value?.hasUpdate) return "Update available"
	if (status.value?.checkedAt) return "You're up to date"
	return "Ready to check"
})

const statusDetail = computed(() => {
	if (status.value?.error) return status.value.error
	if (status.value?.message) return status.value.message
	if (status.value?.hasUpdate && status.value.update) {
		return `v${status.value.currentVersion} -> v${status.value.update.version}`
	}
	if (status.value?.checkedAt) return `ShowRunner v${status.value.currentVersion} is the current installed version.`
	return "Check GitHub Releases to compare this build with the latest published update."
})

async function loadStatus() {
	status.value = await getUpdateStatus()
}

async function checkNow() {
	checking.value = true
	try {
		status.value = await checkForUpdates()
		if (status.value.hasUpdate) {
			feedback.success("Update available", `v${status.value.update?.version}`)
		} else if (status.value.error) {
			feedback.error("Update check failed", status.value.error)
		} else {
			feedback.success("ShowRunner is up to date", `v${status.value.currentVersion}`)
		}
	} catch (err) {
		feedback.error("Update check failed", err)
	} finally {
		checking.value = false
	}
}

async function installUpdate() {
	updating.value = true
	try {
		await updateShowRunner()
	} catch (err) {
		updating.value = false
		feedback.error("Update install failed", err)
	}
}

async function prepareReleaseNoteLinks() {
	await nextTick()
	const links = notes.value?.querySelectorAll("a") ?? []
	for (const link of links) {
		link.target = "_blank"
		link.rel = "noreferrer"
	}
}

watch(sanitizedReleaseNotes, prepareReleaseNoteLinks)

onMounted(async () => {
	await loadStatus()
	if (!status.value?.checkedAt) {
		await checkNow()
	} else {
		await prepareReleaseNoteLinks()
	}
})
</script>

<style scoped>
.updates-page {
	display: flex;
	flex-direction: column;
	gap: 1rem;
	margin: 0 auto;
	max-width: 980px;
	padding: 1rem;
	width: min(980px, 100%);
	box-sizing: border-box;
}

.updates-page__header {
	align-items: flex-start;
	display: flex;
	gap: 1rem;
	justify-content: space-between;
}

.updates-page__header h1,
.updates-page__section-title h2 {
	margin-bottom: 0.25rem;
	margin-top: 0;
}

.updates-page__header p,
.updates-page__status p,
.updates-page__section-title span,
.updates-page__empty {
	color: var(--text-color-secondary);
	margin: 0;
}

.updates-page__actions {
	align-items: center;
	display: flex;
	flex: 0 0 auto;
	flex-wrap: wrap;
	gap: 0.5rem;
	justify-content: flex-end;
}

.updates-page__status {
	align-items: center;
	border: 1px solid var(--surface-400);
	border-left-width: 4px;
	border-radius: var(--border-radius);
	display: grid;
	gap: 1rem;
	grid-template-columns: minmax(0, 1fr) auto;
	padding: 0.9rem 1rem;
}

.updates-page__status--available {
	border-left-color: var(--primary-color);
}

.updates-page__status--current {
	border-left-color: var(--green-400);
}

.updates-page__status--error {
	border-left-color: var(--red-400);
}

.updates-page__status--muted {
	border-left-color: var(--surface-500);
}

.updates-page__meta {
	text-align: right;
}

.updates-page__meta span {
	color: var(--text-color-secondary);
	display: block;
	font-size: 0.85rem;
}

.updates-page__notes {
	border: 1px solid var(--surface-400);
	border-radius: var(--border-radius);
	min-height: 22rem;
	overflow: hidden;
}

.updates-page__section-title {
	align-items: baseline;
	border-bottom: 1px solid var(--surface-400);
	display: flex;
	gap: 1rem;
	justify-content: space-between;
	padding: 0.85rem 1rem;
}

.updates-page__notes-body {
	height: 26rem;
}

.updates-page__notes-inner {
	padding: 1rem;
}

.updates-page__release-notes {
	line-height: 1.5;
}

.updates-page__release-notes :deep(a) {
	color: var(--primary-color);
}

.updates-page__empty {
	padding: 1rem;
}

.updates-page :deep(.p-button) {
	white-space: nowrap;
}

@media (max-width: 640px) {
	.updates-page__header,
	.updates-page__section-title {
		align-items: stretch;
		flex-direction: column;
	}

	.updates-page__actions {
		justify-content: flex-start;
	}

	.updates-page__status {
		grid-template-columns: 1fr;
	}

	.updates-page__meta {
		text-align: left;
	}
}
</style>
