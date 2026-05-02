<template>
	<div class="container">
		<div class="inner-container" ref="containerDiv">
			<p-data-table
				class="flex flex-column"
				scrollable
				data-key="id"
				:value="queues"
				style="width: 100%; max-height: 100%"
				sort-field="config.name"
			>
				<template #header>
					<div class="queue-page__header">
						<div>
							<h2>Queues</h2>
							<p>Queues schedule graph automations for alerts, scene banners, paid events, and other moments that should not overlap.</p>
						</div>
						<p-button icon="mdi mdi-plus" label="Create Queue" @click="createDialog()" />
					</div>
				</template>

				<p-column header="Status" class="column-fit-width">
					<template #body="{ data }: { data: ActionQueueResource }">
						<span class="queue-page__pill" :class="{ paused: data.config.paused, running: Boolean(data.state.running) }">
							<i :class="data.config.paused ? 'mdi mdi-pause' : data.state.running ? 'mdi mdi-play-circle' : 'mdi mdi-check-circle-outline'" />
							{{ data.config.paused ? "Paused" : data.state.running ? "Running" : "Ready" }}
						</span>
					</template>
				</p-column>

				<p-column header="Name" field="config.name"> </p-column>

				<p-column header="Current Item">
					<template #body="{ data }: { data: ActionQueueResource }">
						<span v-if="data.state.running">{{ describeSource(data.state.running.source) }}</span>
						<span v-else class="text-color-secondary">Idle</span>
					</template>
				</p-column>

				<p-column header="Pending" class="column-fit-width">
					<template #body="{ data }: { data: ActionQueueResource }">
						{{ data.state.queue.length }}
					</template>
				</p-column>

				<p-column header="Recent" class="column-fit-width">
					<template #body="{ data }: { data: ActionQueueResource }">
						{{ data.state.history.length }}
					</template>
				</p-column>

				<p-column header="Next Automation">
					<template #body="{ data }: { data: ActionQueueResource }">
						<span v-if="data.state.queue[0]">{{ describeSource(data.state.queue[0].source) }}</span>
						<span v-else class="text-color-secondary">No pending items</span>
					</template>
				</p-column>

				<p-column class="column-fit-width">
					<template #body="{ data }">
						<div class="flex flex-row gap-1">
							<p-button icon="mdi mdi-pencil" text @click="editDialog(data.id)" />
							<p-button icon="mdi mdi-delete" text @click="deleteDialog(data.id)" />
						</div>
					</template>
				</p-column>
			</p-data-table>
		</div>
	</div>
</template>

<script setup lang="ts">
import {
	useResourceArray,
	useResourceEditDialog,
	useResourceCreateDialog,
	useResourceDeleteDialog,
} from "ShowRunner-ui-core"
import { ActionQueueState, ActionQueueConfig, AutomationSource, ResourceData } from "ShowRunner-schema"
import PButton from "primevue/button"
import PDataTable from "primevue/datatable"
import PColumn from "primevue/column"

type ActionQueueResource = ResourceData<ActionQueueConfig, ActionQueueState>

const queues = useResourceArray<ActionQueueResource>("ActionQueue")
const editDialog = useResourceEditDialog("ActionQueue")
const createDialog = useResourceCreateDialog("ActionQueue")
const deleteDialog = useResourceDeleteDialog("ActionQueue")

function describeSource(source: AutomationSource) {
	if (source.type === "automation") return `Automation ${source.id}`
	if (source.type === "profile") return `Profile trigger ${source.subId ?? source.id}`
	if (source.type === "stream-plan") return `Stream plan ${source.subId ?? source.id}`
	return `${source.type}:${source.subId ?? source.id}`
}
</script>

<style scoped>
.container {
	position: relative;
}

.inner-container {
	position: absolute;
	top: 0;
	bottom: 0;
	left: 0;
	right: 0;
	overflow: hidden;
}

.queue-page__header {
	align-items: center;
	display: flex;
	gap: 1rem;
	justify-content: space-between;
}

.queue-page__header h2 {
	margin: 0;
}

.queue-page__header p {
	color: var(--text-color-secondary);
	margin: 0.25rem 0 0;
}

.queue-page__pill {
	align-items: center;
	background: var(--surface-800);
	border: 1px solid var(--surface-600);
	border-radius: 999px;
	display: inline-flex;
	gap: 0.35rem;
	padding: 0.2rem 0.55rem;
	white-space: nowrap;
}

.queue-page__pill.running {
	background: color-mix(in srgb, #54d98c 16%, var(--surface-900));
	border-color: color-mix(in srgb, #54d98c 46%, var(--surface-600));
}

.queue-page__pill.paused {
	background: color-mix(in srgb, #ffcf5a 16%, var(--surface-900));
	border-color: color-mix(in srgb, #ffcf5a 46%, var(--surface-600));
}
</style>
