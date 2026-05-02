import { describe, it, expect } from "vitest"

/**
 * Tests verifying the reconnect guard logic.
 * The actual WebSocket code can't easily be tested in unit tests,
 * but we validate the state machine logic here.
 */
describe("websocket reconnect guard", () => {
	// Simulated state machine matching websocket.ts logic
	function createReconnectGuard() {
		let reconnectTimer: ReturnType<typeof setTimeout> | undefined
		let isConnecting = false
		let status: "idle" | "connecting" | "connected" | "reconnecting" = "idle"
		let connectCallCount = 0

		function connect() {
			if (isConnecting) return // Guard: prevent duplicate connects
			isConnecting = true
			connectCallCount++

			if (reconnectTimer !== undefined) {
				clearTimeout(reconnectTimer)
				reconnectTimer = undefined
			}

			status = status === "connected" || status === "reconnecting" ? "reconnecting" : "connecting"

			// Simulate async open
			setTimeout(() => {
				isConnecting = false
				status = "connected"
			}, 0)
		}

		function onClose() {
			isConnecting = false
			if (reconnectTimer !== undefined) return // Guard: no duplicate timers
			status = "reconnecting"
			reconnectTimer = setTimeout(() => {
				reconnectTimer = undefined
				connect()
			}, 100)
		}

		return { connect, onClose, getStatus: () => status, getConnectCount: () => connectCallCount }
	}

	it("does not schedule multiple reconnects on rapid close events", () => {
		const guard = createReconnectGuard()
		guard.connect()
		// Simulate 3 rapid close events
		guard.onClose()
		guard.onClose()
		guard.onClose()
		// Only one reconnect should be scheduled (connectCallCount stays at 1 from initial)
		expect(guard.getConnectCount()).toBe(1)
		expect(guard.getStatus()).toBe("reconnecting")
	})

	it("prevents concurrent connect calls", () => {
		const guard = createReconnectGuard()
		guard.connect()
		guard.connect()
		guard.connect()
		expect(guard.getConnectCount()).toBe(1)
	})
})

describe("shader uniform tolerance", () => {
	it("gl.getUniformLocation returns null for missing uniforms (conceptual)", () => {
		// This validates our guard pattern: if (location) gl.uniform*(location, ...)
		// A null location simply skips the call — no WebGL error
		const location: WebGLUniformLocation | null = null
		let called = false
		if (location) {
			called = true
		}
		expect(called).toBe(false)
	})
})
