import { describe, expect, it } from "vitest"
import { automationStarterTemplates } from "./automation-starter-templates"

describe("automation starter templates", () => {
	it("includes queue workflow starters with usable graph entries", () => {
		const requiredIds = [
			"youtube-paid-event-alerts-queue",
			"paid-alert-queue-worker",
			"scene-begin-scene-queue",
			"scene-banner-queue-worker",
		]

		for (const id of requiredIds) {
			const template = automationStarterTemplates.find((item) => item.id === id)
			expect(template, id).toBeDefined()
			const config = template!.create()
			expect(config.schemaVersion).toBe(2)
			expect(config.graph.nodes.length).toBeGreaterThan(0)
			expect(config.graph.entryNodeId).toBe(config.graph.nodes[0].id)
		}
	})

	it("includes onboarding starters for common stream workflows", () => {
		const requiredIds = [
			"obs-scene-change",
			"twitch-chat-command-reply",
			"twitch-chat-moderation-review",
			"stream-plan-next-segment",
		]

		for (const id of requiredIds) {
			const template = automationStarterTemplates.find((item) => item.id === id)
			expect(template, id).toBeDefined()
			const config = template!.create()
			expect(config.schemaVersion).toBe(2)
			expect(config.graph.nodes.length).toBeGreaterThan(0)
			expect(config.graph.entryNodeId).toBe(config.graph.nodes[0].id)
		}
	})

	it("keeps starter template ids unique", () => {
		const ids = automationStarterTemplates.map((item) => item.id)
		expect(new Set(ids).size).toBe(ids.length)
	})
})
