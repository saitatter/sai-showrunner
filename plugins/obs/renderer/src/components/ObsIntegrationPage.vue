<template>
	<div class="obs-integration-page">
		<header>
			<i class="obsi obsi-obs obs-blue" />
			<div>
				<h1>OBS Connections</h1>
				<p>Manage the OBS websocket connections used by actions, overlays, and stream automation.</p>
			</div>
		</header>
		<resource-setting-list resource-type="OBSConnection" />
	</div>
</template>

<script setup lang="ts">
import { ResourceSettingList } from "ShowRunner-ui-core"
</script>

<style scoped>
.obs-integration-page {
	display: grid;
	gap: 1rem;
	padding: 1rem;
}

.obs-integration-page header {
	align-items: center;
	display: flex;
	gap: 0.85rem;
}

.obs-integration-page header i {
	font-size: 2rem;
}

.obs-integration-page h1,
.obs-integration-page p {
	margin: 0;
}

.obs-integration-page p {
	color: var(--text-color-secondary);
}
</style>
