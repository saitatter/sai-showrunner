import { defineAction, defineTrigger, onLoad, onUnload, definePlugin } from "ShowRunner-core"

export default definePlugin(
	{
		id: "{{name}}",
		name: "UI Name",
		description: "UI Description",
		icon: "mdi-pencil",
	},
	() => {
		//Plugin Intiialization
	}
)
