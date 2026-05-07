<template>
	<div class="graph-issues-panel">
		<p v-if="!issues.length" class="graph-issues-panel__empty">{{ emptyMessage }}</p>
		<button
			v-for="(issue, index) in issues"
			v-else
			:key="issueKey(issue, index)"
			type="button"
			class="graph-issues-panel__issue"
			:class="`graph-issues-panel__issue--${issue.severity}`"
			:disabled="!isSelectable(issue)"
			@click="emit('select', issue)"
		>
			<i :class="issueIcon(issue.severity)" />
			<span class="graph-issues-panel__body">
				<span class="graph-issues-panel__message">{{ issue.message }}</span>
				<small v-if="issueMeta(issue)" class="graph-issues-panel__meta">{{ issueMeta(issue) }}</small>
			</span>
		</button>
	</div>
</template>

<script setup lang="ts">
import type { GraphIssue, GraphIssueSeverity } from "../../util/graph"

const props = withDefaults(defineProps<{
	issues: GraphIssue[]
	emptyMessage?: string
	selectable?: boolean
}>(), {
	emptyMessage: "No graph issues.",
	selectable: false,
})

const emit = defineEmits<{
	select: [issue: GraphIssue]
}>()

function issueIcon(severity: GraphIssueSeverity) {
	if (severity === "error") return "mdi mdi-alert"
	if (severity === "warning") return "mdi mdi-alert-outline"
	return "mdi mdi-information-outline"
}

function issueMeta(issue: GraphIssue) {
	return [
		issue.nodeId ? `node ${issue.nodeId}` : "",
		issue.portKey ? `port ${issue.portKey}` : "",
		issue.wireId ? `wire ${issue.wireId}` : "",
	].filter(Boolean).join(" / ")
}

function issueKey(issue: GraphIssue, index: number) {
	return issue.code ?? issue.wireId ?? `${issue.severity}:${issue.message}:${index}`
}

function isSelectable(issue: GraphIssue) {
	return props.selectable && Boolean(issue.nodeId || issue.wireId)
}
</script>

<style scoped>
.graph-issues-panel {
	display: flex;
	flex-direction: column;
	gap: 8px;
}

.graph-issues-panel__empty {
	margin: 0;
	color: var(--graph-text-muted, #999);
}

.graph-issues-panel__issue {
	display: grid;
	grid-template-columns: 18px minmax(0, 1fr);
	gap: 8px;
	align-items: flex-start;
	width: 100%;
	padding: 8px 10px;
	border: 1px solid var(--graph-panel-border, #333);
	border-radius: 6px;
	background: var(--graph-panel-background, #111);
	color: inherit;
	font: inherit;
	text-align: left;
}

.graph-issues-panel__issue:not(:disabled) {
	cursor: pointer;
}

.graph-issues-panel__issue:disabled {
	cursor: default;
}

.graph-issues-panel__issue--error i {
	color: #ff6b6b;
}

.graph-issues-panel__issue--warning i {
	color: #ffd166;
}

.graph-issues-panel__issue--info i {
	color: #6ec6ff;
}

.graph-issues-panel__body {
	display: flex;
	min-width: 0;
	flex-direction: column;
	gap: 3px;
}

.graph-issues-panel__message {
	overflow-wrap: anywhere;
}

.graph-issues-panel__meta {
	color: var(--graph-text-muted, #999);
}
</style>
