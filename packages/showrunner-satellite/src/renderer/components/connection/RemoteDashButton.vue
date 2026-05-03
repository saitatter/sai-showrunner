<template>
	<p-button @click="startConnection"> {{ option.name }}</p-button>
</template>

<script setup lang="ts">
import PButton from "primevue/button"
import { SatelliteConnectionOption } from "showrunner-schema"
import { usePluginStore, useSatelliteConnection } from "showrunner-ui-core"
import { useChannelAccountResource } from "showrunner-plugin-twitch-renderer"

const props = defineProps<{
	option: SatelliteConnectionOption
}>()

const twitchAccount = useChannelAccountResource()

const satelliteStore = useSatelliteConnection()

function startConnection(ev: MouseEvent) {
	if (!twitchAccount.value?.state.authenticated) return

	satelliteStore.connectToShowRunner({
		satelliteService: "twitch",
		satelliteId: twitchAccount.value.config.twitchId,
		ShowRunnerService: "twitch",
		ShowRunnerId: props.option.remoteUserId,
		dashId: props.option.typeId,
	})
}
</script>
