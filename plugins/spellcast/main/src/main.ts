import {
	defineAction,
	defineTrigger,
	onLoad,
	onUnload,
	definePlugin,
	reactiveRef,
	onCloudPubSubMessage,
} from "ShowRunner-core"
import { TwitchViewer } from "ShowRunner-plugin-twitch-shared"
import { setupSpells, SpellHook } from "./spell"

export default definePlugin(
	{
		id: "spellcast",
		name: "SpellCast",
		description: "UI Description",
		icon: "sci sci-spellcast",
		color: "#488EE2",
	},
	() => {
		setupSpells()
	}
)

export { SpellHook }
