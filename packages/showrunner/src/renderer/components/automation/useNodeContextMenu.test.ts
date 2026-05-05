import { computed } from "vue"
import { describe, expect, it } from "vitest"
import { useNodeContextMenu } from "./useNodeContextMenu"

function makePluginStore(disabledIds: string[] = []) {
	const disabled = new Set(disabledIds)
	return {
		pluginMap: new Map([
			[
				"ShowRunner",
				{
					id: "ShowRunner",
					name: "ShowRunner",
					icon: "mdi mdi-webcam",
					color: "#de84ff",
					triggers: {},
					actions: {
						convertStringToNumber: { name: "Convert String To Number", icon: "mdi mdi-swap-horizontal", type: "regular" },
						"convert-json-string-to-object": { name: "Convert JSON String To Object", icon: "mdi mdi-code-json", type: "regular" },
						addToQueue: { name: "Add to Queue", icon: "mdi mdi-tray-plus", type: "regular" },
					},
				},
			],
			[
				"obs",
				{
					id: "obs",
					name: "OBS",
					icon: "mdi mdi-broadcast",
					color: "#64b5f6",
					triggers: {
						sceneBegin: { name: "Scene Begin", icon: "mdi mdi-play" },
					},
					actions: {
						scene: { name: "Switch Scene", icon: "mdi mdi-monitor", type: "regular" },
						branch: { name: "Legacy Branch", icon: "mdi mdi-source-branch", type: "flow" },
					},
				},
			],
			[
				"sound",
				{
					id: "sound",
					name: "Sound",
					icon: "mdi mdi-volume-high",
					color: "#ffcf5a",
					triggers: {},
					actions: {
						play: { name: "Play Sound", icon: "mdi mdi-play", type: "regular" },
					},
				},
			],
			[
				"overlays",
				{
					id: "overlays",
					name: "Overlays",
					icon: "mdi mdi-layers",
					color: "#ce93d8",
					triggers: {},
					actions: {
						paidAlert: { name: "Paid Alert Overlay", icon: "mdi mdi-bell", type: "regular" },
					},
				},
			],
			[
				"twitch",
				{
					id: "twitch",
					name: "Twitch",
					icon: "mdi mdi-twitch",
					color: "#9146ff",
					triggers: {},
					actions: {
						chat: { name: "Send Chat Message", icon: "mdi mdi-message-text", type: "regular" },
					},
				},
			],
		]),
		isPluginEnabled(id: string) {
			return !disabled.has(id)
		},
	}
}

function createContextMenu(disabledIds: string[] = []) {
	return useNodeContextMenu(
		computed(() => [{ id: "node-1", title: "Node 1" }]),
		makePluginStore(disabledIds),
		(clientX, clientY) => ({ x: clientX, y: clientY }),
		() => ({ id: "main" })
	)
}

describe("useNodeContextMenu", () => {
	it("keeps categories collapsed while data conversions are visible by default", () => {
		const menu = createContextMenu()

		expect(menu.isContextGroupOpen("categories")).toBe(false)
		expect(menu.isContextGroupOpen("data")).toBe(true)
	})

	it("surfaces matching nodes in search even when their groups are collapsed", () => {
		const menu = createContextMenu()

		menu.toggleContextGroup("actions")
		menu.contextMenuQuery.value = "scene"

		expect(menu.isContextGroupOpen("actions")).toBe(false)
		expect(menu.isContextGroupOpen("action:obs")).toBe(false)
		expect(menu.contextMenuSearchItems.value.map((item) => item.name)).toEqual(["Scene Begin", "Switch Scene"])
	})

	it("omits disabled plugin actions and triggers from grouped and flat search results", () => {
		const menu = createContextMenu(["obs"])

		menu.contextMenuQuery.value = "scene"

		expect(menu.actionContextGroups.value).toEqual([])
		expect(menu.triggerContextGroups.value).toEqual([])
		expect(menu.contextMenuSearchItems.value).toEqual([])
	})

	it("reports search matches that only exist in disabled plugins", () => {
		const menu = createContextMenu(["obs"])

		menu.contextMenuQuery.value = "scene"

		expect(menu.disabledContextMenuSearchItems.value.map((item) => item.key)).toEqual(["obs:sceneBegin", "obs:scene"])
	})

	it("keeps enabled plugin actions available while filtering out flow actions", () => {
		const menu = createContextMenu()

		menu.contextMenuQuery.value = "sound"

		expect(menu.contextMenuSearchItems.value.map((item) => item.key)).toEqual(["sound:play"])
		expect(menu.contextMenuSearchItems.value.some((item) => item.key === "obs:branch")).toBe(false)
	})

	it("groups regular actions into workflow categories", () => {
		const menu = createContextMenu()

		const categoryItems = Object.fromEntries(
			menu.actionCategoryGroups.value.map((group) => [group.id, group.items.map((item) => item.key)])
		)

		expect(categoryItems["data-transforms"]).toContain("ShowRunner:convertStringToNumber")
		expect(categoryItems["data-transforms"]).toContain("ShowRunner:convert-json-string-to-object")
		expect(categoryItems.queues).toContain("ShowRunner:addToQueue")
		expect(categoryItems.overlays).toContain("overlays:paidAlert")
		expect(categoryItems.obs).toContain("obs:scene")
		expect(categoryItems.chat).toContain("twitch:chat")
		expect(categoryItems.utility).toContain("sound:play")
		expect(Object.values(categoryItems).flat()).not.toContain("obs:branch")
	})

	it("filters workflow categories with the context menu query", () => {
		const menu = createContextMenu()

		menu.contextMenuQuery.value = "queue"

		expect(menu.actionCategoryGroups.value.map((group) => group.id)).toEqual(["queues"])
		expect(menu.actionCategoryGroups.value[0].items.map((item) => item.key)).toEqual(["ShowRunner:addToQueue"])
	})

	it("surfaces conversion actions as explicit data-menu items", () => {
		const menu = createContextMenu()

		expect(menu.conversionContextItems.value.map((item) => item.key)).toEqual([
			"ShowRunner:convert-json-string-to-object",
			"ShowRunner:convertStringToNumber",
		])
	})
})
