import { usePluginStore } from "showrunner-ui-core"
import RandomFlowActionComponent from "./components/RandomFlowActionComponent.vue"

export async function initPlugin() {
	const pluginStore = usePluginStore()

	pluginStore.setFlowActionComponent("random", "random", RandomFlowActionComponent)
}
