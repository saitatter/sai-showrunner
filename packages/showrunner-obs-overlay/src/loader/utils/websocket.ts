import { OverlayTransport, OverlayTransportMessage, OverlayTransportStatus, Unsubscribe } from "showrunner-overlay-core"

export class BrowserOverlaySocket implements OverlayTransport {
	private socket?: WebSocket
	private reconnectTimer?: number
	private connecting = false
	private pending?: Promise<void>
	private cancelPending?: () => void
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
			const socket = new WebSocket(`ws://${this.host}?overlay=${encodeURIComponent(this.overlayId)}`)
			this.socket = socket
			this.cancelPending = () => reject(new Error("Overlay connection closed before opening"))
			socket.addEventListener("open", () => {
				if (this.socket !== socket || this.closed) return
				this.connecting = false; this.cancelPending = undefined; this.setStatus("connected"); resolve()
			}, { once: true })
			socket.addEventListener("error", (event) => {
				if (this.socket !== socket) return
				reject(event)
				socket.close()
			}, { once: true })
			socket.addEventListener("message", (event) => {
				if (this.socket !== socket || this.closed || typeof event.data !== "string") return
				try {
					const message = JSON.parse(event.data) as OverlayTransportMessage
					for (const listener of this.listeners) listener(message)
				} catch { /* Ignore malformed transport messages. */ }
			})
				socket.addEventListener("close", () => {
				if (this.socket !== socket) return
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
		if (this.socket?.readyState !== WebSocket.OPEN) return
		this.socket.send(JSON.stringify(message))
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
