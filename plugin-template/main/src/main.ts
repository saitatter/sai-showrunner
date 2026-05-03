import { defineAction, defineTrigger, onLoad, onUnload, definePlugin } from "showrunner-core"

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
