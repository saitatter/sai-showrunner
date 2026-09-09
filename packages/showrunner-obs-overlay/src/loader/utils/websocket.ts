import { OverlayTransport, OverlayTransportMessage, OverlayTransportStatus, Unsubscribe } from "showrunner-overlay-core"

export class BrowserOverlaySocket implements OverlayTransport {
	private socket?: WebSocket
	private reconnectTimer?: number
	private connecting = false
	private closed = false
	private readonly listeners = new Set<(message: OverlayTransportMessage) => void>()
	private readonly statusListeners = new Set<(status: OverlayTransportStatus) => void>()
	private status: OverlayTransportStatus = "idle"

	constructor(private readonly overlayId: string, private readonly host = window.location.host) {}

	async connect(): Promise<void> {
		this.closed = false
		this.setStatus("connecting")
		if (this.socket?.readyState === WebSocket.OPEN) return
		if (this.connecting) return
		this.connecting = true
		await new Promise<void>((resolve, reject) => {
			const socket = new WebSocket(`ws://${this.host}?overlay=${encodeURIComponent(this.overlayId)}`)
			this.socket = socket
			socket.addEventListener("open", () => { this.connecting = false; this.setStatus("connected"); resolve() }, { once: true })
			socket.addEventListener("error", (event) => { this.connecting = false; reject(event) }, { once: true })
			socket.addEventListener("message", (event) => {
				if (typeof event.data !== "string") return
				try {
					const message = JSON.parse(event.data) as OverlayTransportMessage
					for (const listener of this.listeners) listener(message)
				} catch { /* Ignore malformed transport messages. */ }
			})
				socket.addEventListener("close", () => {
					this.socket = undefined
					this.connecting = false
					if (!this.closed && this.reconnectTimer === undefined) {
						this.setStatus("reconnecting")
						this.reconnectTimer = window.setTimeout(() => { this.reconnectTimer = undefined; void this.connect().catch(() => {}) }, 1000)
				}
			})
		})
	}

	async close(): Promise<void> {
		this.closed = true
		this.setStatus("idle")
		if (this.reconnectTimer !== undefined) window.clearTimeout(this.reconnectTimer)
		this.reconnectTimer = undefined
		this.socket?.close()
		this.socket = undefined
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
