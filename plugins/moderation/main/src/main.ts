import { definePlugin, defineRendererCallable, onLoad } from "castmate-core"
import { ModerationService } from "./moderation-service"

export { ModerationService } from "./moderation-service"

declare global {
	var __showrunnerModeration: ModerationService | undefined
}

export default definePlugin(
	{
		id: "moderation",
		name: "Moderation Docker",
		description: "Connects ShowRunner events to the SAI moderation docker.",
		icon: "mdi mdi-shield-check",
		color: "#20D6B5",
	},
	() => {
		const moderation = ModerationService.getInstance()
		globalThis.__showrunnerModeration = moderation

		defineRendererCallable("getStatus", async () => moderation.getStatus())
		defineRendererCallable("saveSettings", async (settings) => moderation.saveSettings(settings))
		defineRendererCallable("checkHealth", async () => moderation.checkHealth())
		defineRendererCallable("reconnect", async () => moderation.reconnect())
		defineRendererCallable("sendTestMessage", async () => moderation.sendTestMessage())

		onLoad(async () => {
			await moderation.initialize()
		})
	}
)
