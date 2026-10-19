import { describe, expect, it, vi } from "vitest"
import { OverlayTransportMessage } from "showrunner-overlay-core"
import { PendingRPCRegistry } from "./pending_rpc"

function createRegistry(timeoutMs = 25): {
	registry: PendingRPCRegistry
	sent: OverlayTransportMessage[]
} {
	const sent: OverlayTransportMessage[] = []
	return {
		sent,
		registry: new PendingRPCRegistry((message) => sent.push(message), timeoutMs),
	}
}

describe("PendingRPCRegistry", () => {
	it("resolves a request from its response and clears its timer", async () => {
		vi.useFakeTimers()
		try {
			const { registry, sent } = createRegistry()
			const request = registry.call<string>("queryViewerData", 0, 10)

			expect(sent).toHaveLength(1)
			registry.handleResponse({ responseId: sent[0].requestId, result: "ok" })

			expect(await request).toBe("ok")
			expect(vi.getTimerCount()).toBe(0)
		} finally {
			vi.useRealTimers()
		}
	})

	it("rejects every request when a connection generation is reset", async () => {
		const { registry } = createRegistry()
		const request = registry.call("widgetRPC", "showAlert")

		const rejection = expect(request).rejects.toThrow("transport reconnecting")
		registry.reset(new Error("transport reconnecting"))

		await rejection
		expect(registry.connectionGeneration).toBe(1)
	})

	it("ignores a response from an invalidated generation", async () => {
		const { registry, sent } = createRegistry()
		const oldRequest = registry.call("oldRequest")
		const oldRequestId = sent[0].requestId
		registry.reset(new Error("disconnected"))
		await expect(oldRequest).rejects.toThrow("disconnected")

		const newRequest = registry.call("newRequest")
		registry.handleResponse({ responseId: oldRequestId, result: "stale" })
		registry.handleResponse({ responseId: sent[1].requestId, result: "fresh" })

		expect(await newRequest).toBe("fresh")
	})

	it("rejects a request when the sender throws", async () => {
		const failure = new Error("socket unavailable")
		const registry = new PendingRPCRegistry(() => {
			throw failure
		}, 25)

		await expect(registry.call("queryViewerData")).rejects.toBe(failure)
	})

	it("rejects a request after its timeout", async () => {
		vi.useFakeTimers()
		try {
			const { registry } = createRegistry(10)
			const request = registry.call("queryViewerData")
			const rejection = expect(request).rejects.toThrow("Overlay RPC timed out: queryViewerData.")

			await vi.advanceTimersByTimeAsync(10)
			await rejection
		} finally {
			vi.useRealTimers()
		}
	})
})
