<template>
	<div ref="pageRef" class="settings-page" @scroll="rememberScroll">
		<div class="settings-page__search">
			<span class="p-input-icon-left">
				<i class="pi pi-search" />
				<p-input-text v-model="filterModel" placeholder="search" />
			</span>
		</div>
		<div class="settings-page__content">
			<template v-for="pluginSettings of filteredSettings" :key="pluginSettings.pluginId">
				<h1
					:style="{ borderBottom: `solid 2px ${pluginStore.pluginMap.get(pluginSettings.pluginId)?.color}` }"
					class="mb-2 mt-1"
				>
					<i
						v-if="pluginStore.pluginMap.get(pluginSettings.pluginId)?.icon"
						class="mr-3"
						:class="pluginStore.pluginMap.get(pluginSettings.pluginId)?.icon"
						:style="{ color: pluginStore.pluginMap.get(pluginSettings.pluginId)?.color }"
					/>{{ pluginStore.pluginMap.get(pluginSettings.pluginId)?.name }}
				</h1>
				<div class="px-3">
					<template v-for="[sid, setting] in Object.entries(pluginSettings.settings)" :key="sid">
						<div v-if="setting.type == 'value' || setting.type == 'secret'" class="mt-5">
							<data-input
								:schema="setting.schema"
								:secret="setting.type == 'secret'"
								v-model="model.settings[pluginSettings.pluginId][sid]"
								:local-path="`settings.${pluginSettings.pluginId}.${sid}`"
							/>
						</div>
						<div v-else-if="setting.type == 'resource'">
							{{ setting.name }}
							<component
								:is="resourceStore.resourceMap.get(setting.resourceId)?.settingComponent"
								:resource-type="setting.resourceId"
							/>
						</div>
						<div v-else-if="setting.type == 'component'">
							<component v-if="setting.component" :is="setting.component" />
						</div>
					</template>
				</div>
			</template>
			<div v-if="filteredSettings.length === 0" class="settings-page__empty">
				<i class="mdi mdi-cog-outline" />
				<strong>No settings found</strong>
				<small>{{ filterModel ? "Try a different search." : "No plugin settings are currently registered." }}</small>
			</div>
		</div>
	</div>
</template>

<script setup lang="ts">
import {
	usePluginStore,
	DataInput,
	useResourceStore,
	SettingDefinition,
	useSettingWatcher,
	useDocumentId,
	useDocument,
} from "showrunner-ui-core"
import { computed, nextTick, onMounted, ref, useModel } from "vue"
import { SettingsDocumentData, SettingsViewData } from "./SettingsTypes"
import PInputText from "primevue/inputtext"

const props = defineProps<{
	modelValue: SettingsDocumentData
	view: SettingsViewData
}>()

const model = useModel(props, "modelValue")
const view = useModel(props, "view")
const pageRef = ref<HTMLElement>()
const filterModel = computed({
	get() {
		return view.value?.filter ?? ""
	},
	set(value: string) {
		if (!view.value) return
		view.value.filter = value
	},
})

const pluginStore = usePluginStore()
const resourceStore = useResourceStore()

const documentId = useDocumentId()

const document = useDocument(() => documentId.value)

useSettingWatcher((plugin, setting, value) => {
	if (!document.value) return
	if (!document.value.data.settings) return
	if (!document.value.data.settings[plugin]) return
	document.value.data.settings[plugin][setting] = value
})

const filteredSettings = computed(() => {
	const filterValue = (view.value?.filter ?? "").toLocaleLowerCase()

	const result: { pluginId: string; settings: Record<string, SettingDefinition> }[] = []
	for (const [pid, plugin] of pluginStore.pluginMap) {
		const pluginSettings = {
			pluginId: pid,
			settings: {} as Record<string, SettingDefinition>,
		}

		for (const sid in plugin.settings) {
			const setting = plugin.settings[sid]
			if (setting.type == "value" || setting.type == "secret") {
				const settingNameStr = setting.schema.name?.toLocaleLowerCase() ?? sid.toLocaleLowerCase()
				if (settingNameStr.includes(filterValue)) {
					pluginSettings.settings[sid] = setting
				}
			} else if (setting.type == "resource") {
				const settingNameStr = setting.name.toLocaleLowerCase()
				if (settingNameStr.includes(filterValue)) {
					pluginSettings.settings[sid] = setting
				}
			} else if (setting.type == "component") {
				const componentId = sid
				if (componentId.includes(filterValue)) {
					pluginSettings.settings[componentId] = setting
				}
			}
		}

		if (Object.keys(pluginSettings.settings).length > 0) {
			result.push(pluginSettings)
		}
	}
	return result
})

function rememberScroll(event: Event) {
	const element = event.currentTarget as HTMLElement
	if (!view.value) return
	view.value.scrollX = element.scrollLeft
	view.value.scrollY = element.scrollTop
}

onMounted(async () => {
	await nextTick()
	if (!pageRef.value || !view.value) return
	pageRef.value.scrollLeft = view.value.scrollX
	pageRef.value.scrollTop = view.value.scrollY
})
</script>

<style scoped>
.settings-page {
	box-sizing: border-box;
	height: 100%;
	overflow: auto;
	padding: 0.75rem 1rem 1rem;
	width: 100%;
}

.settings-page__search {
	margin-bottom: 0.75rem;
}

.settings-page__content {
	display: grid;
	gap: 0.5rem;
}

.settings-page__empty {
	align-items: center;
	color: var(--text-color-secondary);
	display: grid;
	gap: 0.35rem;
	justify-items: center;
	padding: 4rem 1rem;
	text-align: center;
}

.settings-page__empty i {
	font-size: 2rem;
}
</style>
