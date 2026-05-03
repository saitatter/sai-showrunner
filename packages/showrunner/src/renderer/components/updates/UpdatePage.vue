<template>
	<div class="updates-page">
		<div class="updates-page__inner">
			<div class="updates-page__header">
				<div>
					<h1>Updates</h1>
					<p>Current version: v{{ status?.currentVersion ?? "unknown" }}</p>
				</div>
				<div class="updates-page__actions">
					<button type="button" class="updates-page__button" :disabled="!status?.canCheckForUpdates || checking" @click="checkNow">
						<i :class="checking ? 'mdi mdi-loading mdi-spin' : 'mdi mdi-refresh'" />
						<span>Check for updates</span>
					</button>
					<button
						v-if="status?.hasUpdate"
						type="button"
						class="updates-page__button updates-page__button--primary"
						:disabled="updating"
						@click="installUpdate"
					>
						<i :class="updating ? 'mdi mdi-loading mdi-spin' : 'mdi mdi-download'" />
						<span>Update and restart</span>
					</button>
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
	</div>
</template>

<script setup lang="ts">
import { UpdateStatus } from "showrunner-schema"
import { FlexScroller, useAppFeedback, useIpcCaller } from "showrunner-ui-core"
import { computed, nextTick, onMounted, ref, watch } from "vue"
import { releaseNotesToSanitizedHtml } from "../../util/sanitize-html"
import { getUpdateStatusView } from "./update-status-view"

const status = ref<UpdateStatus>()
const checking = ref(false)
const updating = ref(false)
const notes = ref<HTMLElement>()

const feedback = useAppFeedback("Updates")

const getUpdateStatus = useIpcCaller<() => UpdateStatus>("info", "getUpdateStatus")
const checkForUpdates = useIpcCaller<() => Promise<UpdateStatus>>("info", "checkForUpdates")
const updateShowRunner = useIpcCaller<() => Promise<void>>("info", "updateShowRunner")

const latestInfo = computed(() => status.value?.latest ?? status.value?.update)
const sanitizedReleaseNotes = computed(() => releaseNotesToSanitizedHtml(latestInfo.value))
const statusView = computed(() => getUpdateStatusView(status.value))
const latestVersionLabel = computed(() => statusView.value.latestVersionLabel)

const checkedAtLabel = computed(() => {
	if (!status.value?.checkedAt) return ""
	return `Last checked ${new Date(status.value.checkedAt).toLocaleString()}`
})

const statusClass = computed(() => statusView.value.statusClass)
const statusTitle = computed(() => statusView.value.statusTitle)
const statusDetail = computed(() => statusView.value.statusDetail)

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
	box-sizing: border-box;
	height: 100%;
	overflow: auto;
	padding: 1rem;
	width: 100%;
}

.updates-page__inner {
	display: flex;
	flex-direction: column;
	gap: 1rem;
	max-width: 980px;
	width: 100%;
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

.updates-page__button {
	align-items: center;
	background: var(--surface-b);
	border: 1px solid var(--surface-d);
	border-radius: 4px;
	color: var(--text-color);
	cursor: pointer;
	display: inline-flex;
	font: inherit;
	gap: 0.4rem;
	min-height: 2rem;
	padding: 0.4rem 0.7rem;
	white-space: nowrap;
}

.updates-page__button:hover:not(:disabled) {
	background: var(--highlight-bg);
}

.updates-page__button:disabled {
	cursor: default;
	opacity: 0.55;
}

.updates-page__button--primary {
	background: var(--primary-color);
	border-color: var(--primary-color);
	color: var(--primary-color-text);
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
