import { computed } from "vue"
import { describe, expect, it } from "vitest"
import { useNodeContextMenu } from "./useNodeContextMenu"

function makePluginStore(disabledIds: string[] = []) {
	const disabled = new Set(disabledIds)
	return {
		pluginMap: new Map([
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

	it("keeps enabled plugin actions available while filtering out flow actions", () => {
		const menu = createContextMenu()

		menu.contextMenuQuery.value = "sound"

		expect(menu.contextMenuSearchItems.value.map((item) => item.key)).toEqual(["sound:play"])
		expect(menu.contextMenuSearchItems.value.some((item) => item.key === "obs:branch")).toBe(false)
	})
})
