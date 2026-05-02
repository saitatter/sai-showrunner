<template>
	<div class="document-page">
		<div v-if="documentError" class="document-page__error">
			<strong>Document render failed</strong>
			<code>{{ documentError }}</code>
			<small>{{ debugSummary }}</small>
		</div>
		<component
			:is="documentComponent"
			v-else-if="documentComponent && document"
			v-model="documentData"
			v-model:view="documentView"
			tabindex="-1"
			:pageData="pageData"
		/>
		<div v-else class="document-page__error">
			<strong>Document is not ready</strong>
			<small>{{ debugSummary }}</small>
		</div>
	</div>
</template>

<script setup lang="ts">
import { computed, onErrorCaptured, ref, watch } from "vue"
import {
	provideBaseDataBinding,
	provideDocument,
	useDocument,
	useDocumentComponent,
	useDocumentStore,
} from "../../main"

const props = defineProps<{
	pageData: { documentId: string; documentType: string } & Record<string, any>
}>()

const document = useDocument(() => props.pageData.documentId)
const documentStore = useDocumentStore()
const documentComponent = useDocumentComponent(() => document.value?.type)
const documentError = ref("")
provideDocument(() => props.pageData.documentId)

provideBaseDataBinding(() => document.value?.view)

const documentData = computed({
	get() {
		return document.value?.data
	},
	set(data) {
		if (!document.value) return
		if (!data) return

		document.value.dirty = true
		document.value.data = data
	},
})

watch(
	documentData,
	() => {
		if (document.value) {
			document.value.dirty = true
		}
	},
	{ deep: true }
)

const documentView = computed({
	get() {
		return document.value?.viewData
	},
	set(data) {
		if (!document.value) return

		if (!data) return

		document.value.viewData = data
	},
})

const debugSummary = computed(() =>
	JSON.stringify({
		pageData: props.pageData,
		hasDocument: !!document.value,
		documentType: document.value?.type,
		hasComponent: !!documentComponent.value,
		hasData: !!document.value?.data,
		hasViewData: !!document.value?.viewData,
		registeredComponents: [...documentStore.documentComponents.keys()],
	})
)

onErrorCaptured((error, instance, info) => {
	documentError.value = error instanceof Error ? error.stack || error.message : String(error)
	console.error("[ShowRunner DocumentPage] child render failed", {
		error,
		info,
		instance,
		debug: JSON.parse(debugSummary.value),
	})
	return false
})
</script>

<style scoped>
.document-page {
	width: 100%;
	height: 100%;
	min-height: 0;
}

.document-page__error {
	display: grid;
	align-content: start;
	gap: 0.75rem;
	margin: 1rem;
	border: 1px solid rgba(255, 120, 120, 0.45);
	border-radius: 6px;
	background: rgba(50, 10, 14, 0.82);
	color: #ffe8e8;
	padding: 1rem;
	white-space: pre-wrap;
}

.document-page__error code,
.document-page__error small {
	color: #ffd0d0;
	font-size: 0.8rem;
	word-break: break-word;
}
</style>
