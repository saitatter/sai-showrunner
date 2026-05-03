<template>
	<div class="setup-dialog">
		<div class="setup-step" v-if="step == 'twitch'">
			<setup-accounts v-model:ready="ready" />
		</div>
		<div class="setup-step" v-else-if="step == 'youtube'">
			<setup-youtube v-model:ready="ready" />
		</div>
		<div class="setup-step" v-else-if="step == 'obs'">
			<setup-obs v-model:ready="ready" />
		</div>
		<div class="setup-step" v-else-if="step == 'done'">
			<setup-done />
		</div>
		<p-divider />
		<div class="flex flex-row justify-content-center align-items-center gap-1" v-if="step != 'done'">
			<div class="flex-grow-1"></div>
			<p-button @click="moveNextStep" :disabled="!ready"> Next </p-button>
			<div class="flex-grow-1 flex flex-row justify-content-end w-0">
				<p-button outlined @click="moveNextStep"> Skip </p-button>
			</div>
		</div>
		<div class="flex flex-row justify-content-center align-items-center" v-else>
			<p-button @click="done"> Get Started! </p-button>
		</div>
	</div>
</template>

<script setup lang="ts">
import SetupObs from "./SetupObs.vue"
import SetupAccounts from "./SetupAccounts.vue"
import SetupYoutube from "./SetupYoutube.vue"
import SetupDone from "./SetupDone.vue"
import PButton from "primevue/button"
import PDivider from "primevue/divider"
import { ref } from "vue"
import {
	createProfileViewData,
	useDialogRef,
	useDockingStore,
	useOpenProfileDocument,
	useResource,
	useResourceArray,
	useResourceStore,
} from "showrunner-ui-core"
import { ProfileConfig } from "showrunner-schema"
import { ResourceData } from "showrunner-schema"

const step = ref("twitch")

const ready = ref(false)

function moveNextStep() {
	if (step.value == "twitch") {
		step.value = "youtube"
		ready.value = false
	} else if (step.value == "youtube") {
		step.value = "obs"
	} else if (step.value == "obs") {
		step.value = "done"
		ensureMainProfile()
	}
}

const dialogRef = useDialogRef()

const resourceStore = useResourceStore()
const profiles = useResourceArray<ResourceData<ProfileConfig>>("Profile")

const mainProfileId = ref<string>()

async function ensureMainProfile() {
	const mainProfile = profiles.value.find((p) => p.config.name == "Main")

	if (mainProfile) {
		mainProfileId.value = mainProfile.id
		return
	}

	mainProfileId.value = await resourceStore.createResource("Profile", "Main")
}

const dockingStore = useDockingStore()

const openProfile = useOpenProfileDocument()

function openMainProfile() {
	if (!mainProfileId.value) return
	openProfile(mainProfileId.value)
}

function done() {
	openMainProfile()
	dialogRef.value?.close()
}
</script>

<style scoped>
.setup-step {
}
</style>
