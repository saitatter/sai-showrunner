import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"

// Mock ShowRunner-core
vi.mock("ShowRunner-core", () => ({
	ensureDirectory: vi.fn(),
	ensureYAML: vi.fn(),
	loadYAML: vi.fn(() => Promise.resolve({})),
	resolveProjectPath: vi.fn((p: string) => `/fake/${p}`),
	usePluginLogger: vi.fn(() => ({ log: vi.fn(), error: vi.fn() })),
	writeYAML: vi.fn(),
}))

// Mock ws
vi.mock("ws", () => ({
	default: vi.fn(),
	__esModule: true,
}))

import { ModerationService } from "../moderation-service"

// Reset singleton between tests
function freshService(): ModerationService {
	// Access private static to reset
	;(ModerationService as any).instance = undefined
	return ModerationService.getInstance()
}

describe("ModerationService - singleton", () => {
	beforeEach(() => {
		;(ModerationService as any).instance = undefined
	})

	it("should return the same instance", () => {
		const a = ModerationService.getInstance()
		const b = ModerationService.getInstance()
		expect(a).toBe(b)
	})

	it("should create a new instance after reset", () => {
		const a = ModerationService.getInstance()
		;(ModerationService as any).instance = undefined
		const b = ModerationService.getInstance()
		expect(a).not.toBe(b)
	})
})

describe("ModerationService - getStatus", () => {
	it("should return default status when not initialized", () => {
		const service = freshService()
		const status = service.getStatus()
		expect(status.enabled).toBe(false)
		expect(status.health).toBe("unknown")
		expect(status.processedMessages).toBe(0)
	})
})

describe("ModerationService - checkHealth", () => {
	beforeEach(() => {
		vi.stubGlobal("fetch", vi.fn())
	})
	afterEach(() => {
		vi.unstubAllGlobals()
	})

	it("should skip health check when disabled", async () => {
		const service = freshService()
		const status = await service.checkHealth()
		expect(status.health).toBe("unknown")
		expect(status.statusMessage).toContain("disabled")
		expect(fetch).not.toHaveBeenCalled()
	})

	it("should set healthy on 200 response", async () => {
		const service = freshService()
		await service.saveSettings({ enabled: true, apiBaseUrl: "http://localhost:8787", apiToken: "tok" })

		;(fetch as any).mockResolvedValue({ ok: true })
		const status = await service.checkHealth()
		expect(status.health).toBe("healthy")
		expect(status.statusMessage).toContain("reachable")
	})

	it("should set error on non-ok response", async () => {
		const service = freshService()
		await service.saveSettings({ enabled: true, apiBaseUrl: "http://localhost:8787" })

		;(fetch as any).mockResolvedValue({ ok: false, status: 503 })
		const status = await service.checkHealth()
		expect(status.health).toBe("error")
		expect(status.statusMessage).toContain("503")
	})

	it("should set error on network failure", async () => {
		const service = freshService()
		await service.saveSettings({ enabled: true, apiBaseUrl: "http://localhost:8787" })

		;(fetch as any).mockRejectedValue(new Error("ECONNREFUSED"))
		const status = await service.checkHealth()
		expect(status.health).toBe("error")
		expect(status.statusMessage).toContain("ECONNREFUSED")
	})

	it("should include auth header when token is set", async () => {
		const service = freshService()
		await service.saveSettings({ enabled: true, apiBaseUrl: "http://localhost:8787", apiToken: "secret" })

		;(fetch as any).mockResolvedValue({ ok: true })
		await service.checkHealth()

		const callArgs = (fetch as any).mock.calls[0]
		expect(callArgs[1].headers).toEqual(expect.objectContaining({ authorization: "Bearer secret" }))
	})
})

describe("ModerationService - forwardChatMessage", () => {
	beforeEach(() => {
		vi.stubGlobal("fetch", vi.fn())
	})
	afterEach(() => {
		vi.unstubAllGlobals()
	})

	const chatEvent = {
		id: "msg-1",
		platform: "twitch" as const,
		source: "twitch",
		receivedAt: "2025-01-01T00:00:00Z",
		actor: { id: "u1", name: "user", displayName: "User", badges: [] },
		payload: { message: "hello" },
	}

	it("should not forward when disabled", async () => {
		const service = freshService()
		await service.forwardChatMessage(chatEvent)
		expect(fetch).not.toHaveBeenCalled()
	})

	it("should not forward youtube when forwardYouTube is false", async () => {
		const service = freshService()
		await service.saveSettings({ enabled: true, forwardYouTube: false })
		;(fetch as any).mockResolvedValue({ ok: true })

		await service.forwardChatMessage({ ...chatEvent, platform: "youtube" as any })
		// fetch is called by saveSettings (health check), but not by forwardChatMessage
		const postCalls = (fetch as any).mock.calls.filter((c: any[]) => c[1]?.method === "POST")
		expect(postCalls.length).toBe(0)
	})

	it("should forward when enabled and increment processedMessages", async () => {
		const service = freshService()
		;(fetch as any).mockResolvedValue({ ok: true })
		await service.saveSettings({ enabled: true })

		const statusBefore = service.getStatus()
		const countBefore = statusBefore.processedMessages

		;(fetch as any).mockResolvedValue({ ok: true })
		await service.forwardChatMessage(chatEvent)

		const statusAfter = service.getStatus()
		expect(statusAfter.processedMessages).toBe(countBefore + 1)
	})

	it("should set error status on failure", async () => {
		const service = freshService()
		;(fetch as any).mockResolvedValue({ ok: true })
		await service.saveSettings({ enabled: true })

		;(fetch as any).mockResolvedValue({ ok: false, status: 500 })
		await service.forwardChatMessage(chatEvent)

		const status = service.getStatus()
		expect(status.health).toBe("error")
		expect(status.statusMessage).toContain("500")
	})
})

describe("ModerationService - moderateChatMessage", () => {
	beforeEach(() => {
		vi.stubGlobal("fetch", vi.fn())
	})
	afterEach(() => {
		vi.unstubAllGlobals()
	})

	it("should return disabled result when not enabled", async () => {
		const service = freshService()
		const result = await service.moderateChatMessage({
			messageId: "m1",
			platform: "twitch",
			viewerName: "User",
			message: "test",
		} as any)
		expect(result.verdict).toBe("disabled")
		expect(result.status).toBe("disabled")
	})

	it("should return action result on success", async () => {
		const service = freshService()
		;(fetch as any).mockResolvedValue({ ok: true })
		await service.saveSettings({ enabled: true })

		;(fetch as any).mockResolvedValue({
			ok: true,
			json: () => Promise.resolve({ moderation: { verdict: "allow", confidence: 0.95, category: "safe" } }),
		})

		const result = await service.moderateChatMessage({
			messageId: "m2",
			platform: "twitch",
			viewerName: "Viewer",
			message: "hello",
		} as any)

		expect(result.verdict).toBe("allow")
		expect(result.approved).toBe(true)
		expect(result.blocked).toBe(false)
		expect(result.confidence).toBe(0.95)
	})

	it("should return flagged result on network error", async () => {
		const service = freshService()
		;(fetch as any).mockResolvedValue({ ok: true })
		await service.saveSettings({ enabled: true })

		;(fetch as any).mockRejectedValue(new Error("timeout"))

		const result = await service.moderateChatMessage({
			messageId: "m3",
			platform: "twitch",
			viewerName: "User",
			message: "test",
		} as any)

		expect(result.verdict).toBe("flag")
		expect(result.flagged).toBe(true)
		expect(result.reason).toContain("timeout")
	})

	it("should parse badges from comma-separated string", async () => {
		const service = freshService()
		;(fetch as any).mockResolvedValue({ ok: true })
		await service.saveSettings({ enabled: true })

		;(fetch as any).mockResolvedValue({
			ok: true,
			json: () => Promise.resolve({ moderation: { verdict: "allow" } }),
		})

		await service.moderateChatMessage({
			messageId: "m4",
			platform: "twitch",
			viewerName: "User",
			message: "hi",
			badges: "subscriber,vip",
		} as any)

		const callBody = JSON.parse((fetch as any).mock.calls.at(-1)[1].body)
		expect(callBody.badges).toEqual(["subscriber", "vip"])
	})
})

describe("ModerationService - saveSettings", () => {
	beforeEach(() => {
		vi.stubGlobal("fetch", vi.fn(() => Promise.resolve({ ok: true })))
	})
	afterEach(() => {
		vi.unstubAllGlobals()
	})

	it("should normalize settings and return updated status", async () => {
		const service = freshService()
		const status = await service.saveSettings({
			enabled: true,
			apiBaseUrl: "http://custom:9999",
			apiToken: "abc",
		})
		expect(status.enabled).toBe(true)
		expect(status.apiBaseUrl).toBe("http://custom:9999")
		expect(status.apiToken).toBe("abc")
	})

	it("should use default URL when empty string provided", async () => {
		const service = freshService()
		const status = await service.saveSettings({ apiBaseUrl: "" })
		expect(status.apiBaseUrl).toBe("http://localhost:8787")
	})
})
