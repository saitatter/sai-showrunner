import { defineAction, defineTrigger, onLoad, onUnload, definePlugin } from "ShowRunner-core"

import { setupKeyboard } from "./keyboard"
import { InputInterface } from "ShowRunner-plugin-input-native"

import { setupMouse } from "./mouse"

export default definePlugin(
	{
		id: "input",
		name: "Input",
		description: "Input!",
		icon: "mdi mdi-keyboard",
		color: "#826262",
	},
	() => {
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
