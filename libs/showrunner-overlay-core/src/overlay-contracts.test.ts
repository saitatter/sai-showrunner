import { describe, expect, it } from "vitest"
import type { OverlayCommandMap, OverlayEventMap, OverlayWidgetConfigFor } from "./overlay-core-main"

describe("generated overlay contracts", () => {
	it("exposes typed widget config and command payloads", () => {
		const config = { duration: 4 } satisfies OverlayWidgetConfigFor<"overlays.alert">
		const args: OverlayCommandMap["showAlert"]["args"] = ["Title", "Message"]

		expect(config.duration).toBe(4)
		expect(args[0]).toBe("Title")
	})

	it("exposes generated event payloads to plugin code", () => {
		const event: OverlayEventMap["showrunner_chat_message"] = { displayName: "Viewer", message: "Hello" }

		expect(event.displayName).toBe("Viewer")
	})
})
