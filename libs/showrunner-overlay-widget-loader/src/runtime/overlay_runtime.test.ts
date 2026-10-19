import { describe, expect, it, vi } from "vitest"
import { OverlayTransport, OverlayTransportMessage, OverlayTransportStatus, Unsubscribe } from "showrunner-overlay-core"
import { OverlayRuntime } from "./overlay_runtime"
import { WidgetRegistry } from "../registry/widget_registry"

class TestTransport implements OverlayTransport {
	readonly sent: OverlayTransportMessage[] = []
	private readonly messageListeners = new Set<(message: OverlayTransportMessage) => void>()
	private readonly statusListeners = new Set<(status: OverlayTransportStatus) => void>()
	private status: OverlayTransportStatus = "idle"

	async connect(): Promise<void> {
		this.emitStatus("connected")
	}

	async close(): Promise<void> {
		this.emitStatus("idle")
	}

	send(message: OverlayTransportMessage): void {
		this.sent.push(message)
	}

	onMessage(listener: (message: OverlayTransportMessage) => void): Unsubscribe {
		this.messageListeners.add(listener)
		return () => this.messageListeners.delete(listener)
	}

	onStatus(listener: (status: OverlayTransportStatus) => void): Unsubscribe {
		this.statusListeners.add(listener)
		listener(this.status)
		return () => this.statusListeners.delete(listener)
	}

	emitStatus(status: OverlayTransportStatus): void {
		this.status = status
		for (const listener of this.statusListeners) listener(status)
	}

	respond(responseId: string, result: unknown): void {
		for (const listener of this.messageListeners) listener({ responseId, result })
	}
}

function createRuntime(transport: TestTransport, rpcTimeoutMs = 50): OverlayRuntime {
	return new OverlayRuntime({
		root: {} as HTMLElement,
		transport,
		registry: new WidgetRegistry(),
		overlayId: "test-overlay",
		rpcTimeoutMs,
	})
}

function callBackend(runtime: OverlayRuntime, name: string, ...args: unknown[]): Promise<unknown> {
	return (runtime as unknown as { callBackend: (name: string, ...args: unknown[]) => Promise<unknown> }).callBackend(
		name,
		...args,
	)
}

function viewerDataQuery(runtime: OverlayRuntime): Promise<unknown> {
	const viewerData = (runtime as unknown as { viewerData: { query: (...args: unknown[]) => Promise<unknown> } })
		.viewerData
	return viewerData.query(0, 10)
}

describe("OverlayRuntime RPC lifecycle", () => {
	it("rejects viewer-data queries when the transport disconnects", async () => {
		const transport = new TestTransport()
		const runtime = createRuntime(transport)
		await runtime.start()

		const query = viewerDataQuery(runtime)
		const rejection = expect(query).rejects.toThrow("Overlay transport reconnecting.")
		transport.emitStatus("reconnecting")

		await rejection
		await runtime.stop()
	})

	it("rejects widget RPCs when the transport disconnects", async () => {
		const transport = new TestTransport()
		const runtime = createRuntime(transport)
		await runtime.start()

		const request = callBackend(runtime, "overlays_widgetRPC", "spinWheel", "widget-1")
		const rejection = expect(request).rejects.toThrow("Overlay transport reconnecting.")
		transport.emitStatus("reconnecting")

		await rejection
		await runtime.stop()
	})

	it("rejects an RPC after its timeout and cancels the pending entry", async () => {
		vi.useFakeTimers()
		try {
			const transport = new TestTransport()
			const runtime = createRuntime(transport, 25)
			await runtime.start()

			const request = callBackend(runtime, "overlays_queryViewerData", 0, 10)
			const rejection = expect(request).rejects.toThrow("Overlay RPC timed out: overlays_queryViewerData.")
			await vi.advanceTimersByTimeAsync(25)

			await rejection
			expect(vi.getTimerCount()).toBe(0)
			await runtime.stop()
		} finally {
			vi.useRealTimers()
		}
	})

	it("ignores a late response from the disconnected generation", async () => {
		const transport = new TestTransport()
		const runtime = createRuntime(transport)
		await runtime.start()

		const request = callBackend(runtime, "overlays_widgetRPC", "showAlert", "widget-1")
		const requestId = transport.sent[0].requestId!
		const rejection = expect(request).rejects.toThrow()
		transport.emitStatus("reconnecting")
		await rejection

		transport.emitStatus("connected")
		transport.respond(requestId, "late")
		await Promise.resolve()
		await runtime.stop()
	})

	it("rejects pending RPCs when the runtime stops", async () => {
		const transport = new TestTransport()
		const runtime = createRuntime(transport)
		await runtime.start()

		const request = callBackend(runtime, "overlays_queryViewerData", 0, 10)
		const rejection = expect(request).rejects.toThrow("Overlay runtime stopped.")
		await runtime.stop()

		await rejection
	})

	it("cancels the timeout when a response arrives", async () => {
		vi.useFakeTimers()
		try {
			const transport = new TestTransport()
			const runtime = createRuntime(transport, 25)
			await runtime.start()

			const request = callBackend(runtime, "overlays_getViewerVariables")
			const requestId = transport.sent[0].requestId!
			transport.respond(requestId, [{ name: "points" }])
			await expect(request).resolves.toEqual([{ name: "points" }])
			expect(vi.getTimerCount()).toBe(0)
			await runtime.stop()
		} finally {
			vi.useRealTimers()
		}
	})
})
