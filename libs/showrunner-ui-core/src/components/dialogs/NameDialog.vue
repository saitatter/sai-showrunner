<template>
	<div>
		<form @submit.prevent="create">
			<p-input-group class="mt-1">
				<p-float-label variant="on">
					<p-input-text id="l" v-model="name" ref="nameInput" autofocus />
					<label for="l"> {{ props.label }} </label>
				</p-float-label>
			</p-input-group>
			<small v-if="nameError" class="p-error">{{ nameError }}</small>
			<div class="flex justify-content-end mt-1">
				<p-button type="submit" label="Create" :disabled="Boolean(nameError)"></p-button>
			</div>
		</form>
	</div>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from "vue"
import PInputText from "primevue/inputtext"
import PButton from "primevue/button"
import PInputGroup from "primevue/inputgroup"
import PFloatLabel from "primevue/floatlabel"
import { useDialogRef } from "../../util/dialog-helper" //Wtf primevue

const dialogRef = useDialogRef()

const props = withDefaults(
	defineProps<{
		label?: string
	}>(),
	{
		label: "Name",
	}
)

const name = ref<string>("")
const normalizedName = computed(() => name.value.trim())
const nameError = computed(() => normalizedName.value ? "" : `${props.label} cannot be empty.`)

onMounted(() => {
	const existingName = dialogRef.value?.data?.existingName
	if (typeof existingName === "string") name.value = existingName
})

function create() {
	if (nameError.value) return
	dialogRef.value?.close(normalizedName.value)
}

/*
const name = computed({
	get() {
		return (dialogRef?.value?.data as { name: string })?.name ?? ""
	},
	set(v) {
		if (!dialogRef || !dialogRef.value) {
			return
		}

		dialogRef.value.data = { name: v }
	},
})
*/
</script>

<style scoped></style>
