import { defineAction, defineTrigger, onLoad, onUnload, definePlugin } from "ShowRunner-core"

import { setupKeyboard } from "./keyboard"
import { setupMouse } from "./mouse"

let InputInterface: any

try {
	InputInterface = require("ShowRunner-plugin-input-native").InputInterface
} catch (e) {
	console.warn("[input plugin] Native bindings not available — plugin disabled.", (e as Error).message)
}

export default definePlugin(
	{
		id: "input",
		name: "Input",
		description: "Input!",
		icon: "mdi mdi-keyboard",
		color: "#826262",
	},
	() => {
		if (!InputInterface) return

		const inputInterface = new InputInterface()

		onLoad(() => {
			inputInterface.startEvents()
		})

		onUnload(() => {
			inputInterface.stopEvents()
		})

		setupKeyboard(inputInterface)
		setupMouse(inputInterface)
	}
)
