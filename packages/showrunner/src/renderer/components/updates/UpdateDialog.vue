<template>
	<div v-if="updateData" class="flex flex-column">
		<div>
			<h4 class="my-2 text-center">New Update</h4>
			<h2 class="my-2 text-center">{{ updateData.version }} - {{ updateData.name }}</h2>
		</div>
		<flex-scroller class="flex-grow-1 update-notes mb-3" inner-class="px-4" style="height: 50vh">
			<div ref="notes" v-html="sanitizedNotes"></div>
		</flex-scroller>
		<div class="flex flex-row">
			<p-button @click="doUpdate" :loading="updating">Update!</p-button>
			<div class="flex-grow-1" />
			<p-button outlined @click="cancel">Skip</p-button>
		</div>
	</div>
</template>

<script setup lang="ts">
import { UpdateData } from "showrunner-schema"
import { useIpcCaller, FlexScroller, useDialogRef } from "showrunner-ui-core"
import { computed, nextTick, onMounted, ref } from "vue"
import PButton from "primevue/button"
import { releaseNotesToSanitizedHtml } from "../../util/sanitize-html"

const updateData = ref<UpdateData>()
const sanitizedNotes = computed(() => releaseNotesToSanitizedHtml(updateData.value))

const getUpdateData = useIpcCaller<() => UpdateData | undefined>("info", "getUpdateInfo")

const updateShowRunner = useIpcCaller<() => any>("info", "updateShowRunner")

const notes = ref<HTMLElement>()

onMounted(async () => {
	updateData.value = await getUpdateData()
	nextTick(() => {
		const links = notes.value?.querySelectorAll("a") ?? []
		for (const link of links) {
			link.target = "_blank"
			link.rel = "noreferrer"
		}
	})
})

const dialogRef = useDialogRef()

function cancel() {
	dialogRef.value?.close()
}

const updating = ref(false)
async function doUpdate() {
	updating.value = true
	await updateShowRunner()
}
</script>

<style scoped>
.update-notes {
	background: var(--surface-b);
	border-radius: var(--border-radius);
}
</style>
