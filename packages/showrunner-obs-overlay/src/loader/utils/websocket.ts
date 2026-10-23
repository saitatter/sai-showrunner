import { OverlayTransport, OverlayTransportMessage, OverlayTransportStatus, Unsubscribe, decodeOverlayWire, encodeOverlayWire } from "showrunner-overlay-core"

export class BrowserOverlaySocket implements OverlayTransport {
	private socket?: WebSocket
	private reconnectTimer?: number
	private connecting = false
	private pending?: Promise<void>
	private cancelPending?: () => void
	private connectionTimer?: number
	private closed = false
	private readonly listeners = new Set<(message: OverlayTransportMessage) => void>()
	private readonly statusListeners = new Set<(status: OverlayTransportStatus) => void>()
	private status: OverlayTransportStatus = "idle"

	constructor(private readonly overlayId: string, private readonly host = window.location.host) {}

	connect(): Promise<void> {
		if (this.socket?.readyState === WebSocket.OPEN) return Promise.resolve()
		if (this.connecting && this.pending) return this.pending
		this.closed = false
		if (this.reconnectTimer !== undefined) window.clearTimeout(this.reconnectTimer)
		this.reconnectTimer = undefined
		this.setStatus("connecting")
		this.connecting = true
		this.pending = new Promise<void>((resolve, reject) => {
			const scheme = window.location.protocol === "https:" ? "wss" : "ws"
			const socket = new WebSocket(`${scheme}://${this.host}?overlay=${encodeURIComponent(this.overlayId)}`)
			this.socket = socket
			this.cancelPending = () => reject(new Error("Overlay connection closed before opening"))
			this.connectionTimer = window.setTimeout(() => {
				if (this.socket !== socket) return
				reject(new Error("Overlay connection timed out"))
				socket.close()
			}, 20000)
			socket.addEventListener("open", () => {
				if (this.socket !== socket || this.closed) return
				this.clearConnectionTimer()
				this.connecting = false; this.cancelPending = undefined; this.setStatus("connected"); resolve()
			}, { once: true })
			socket.addEventListener("error", () => {
				if (this.socket !== socket) return
				this.clearConnectionTimer()
				reject(new Error("Overlay connection failed"))
				socket.close()
			}, { once: true })
			socket.addEventListener("message", (event) => {
				if (this.socket !== socket || this.closed) return
				if (typeof event.data !== "string") { socket.close(1003); return }
				if (event.data.length > 1024 * 1024 || new TextEncoder().encode(event.data).length > 1024 * 1024) {
					socket.close(1009); return
				}
				try {
                    const message = decodeOverlayWire(JSON.parse(event.data), this.overlayId)
					for (const listener of this.listeners) listener(message)
				} catch { socket.close(1007) }
			})
				socket.addEventListener("close", () => {
				if (this.socket !== socket) return
				this.clearConnectionTimer()
				this.cancelPending?.()
				this.cancelPending = undefined
					this.socket = undefined
					this.connecting = false
					if (!this.closed && this.reconnectTimer === undefined) {
						this.setStatus("reconnecting")
						this.reconnectTimer = window.setTimeout(() => { this.reconnectTimer = undefined; void this.connect().catch(() => {}) }, 1000)
				}
			})
		})
		return this.pending
	}

	async close(): Promise<void> {
		this.closed = true
		this.clearConnectionTimer()
		this.setStatus("idle")
		if (this.reconnectTimer !== undefined) window.clearTimeout(this.reconnectTimer)
		this.reconnectTimer = undefined
		this.cancelPending?.()
		this.cancelPending = undefined
		this.connecting = false
		this.pending = undefined
		const socket = this.socket
		this.socket = undefined
		socket?.close()
	}

	send(message: OverlayTransportMessage): void {
		if (this.socket?.readyState !== WebSocket.OPEN) throw new Error("Overlay connection is closed")
		const encoded = JSON.stringify(encodeOverlayWire(message, this.overlayId))
		if (encoded.length > 1024 * 1024 || new TextEncoder().encode(encoded).length > 1024 * 1024) throw new Error("Overlay message limit reached")
		if (this.socket.bufferedAmount > 1024 * 1024) { this.socket.close(1008); throw new Error("Overlay send buffer limit reached") }
		this.socket.send(encoded)
	}

	private clearConnectionTimer(): void {
		if (this.connectionTimer !== undefined) window.clearTimeout(this.connectionTimer)
		this.connectionTimer = undefined
	}

	onMessage(listener: (message: OverlayTransportMessage) => void): Unsubscribe {
		this.listeners.add(listener)
		return () => this.listeners.delete(listener)
	}

	onStatus(listener: (status: OverlayTransportStatus) => void): Unsubscribe {
		this.statusListeners.add(listener)
		listener(this.status)
		return () => this.statusListeners.delete(listener)
	}

	private setStatus(status: OverlayTransportStatus): void {
		this.status = status
		for (const listener of this.statusListeners) listener(status)
	}
}
