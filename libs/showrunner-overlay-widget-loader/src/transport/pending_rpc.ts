import { OverlayTransportMessage } from "showrunner-overlay-core"

interface PendingCall {
	resolve: (value: unknown) => void
	reject: (reason: unknown) => void
	timeout: ReturnType<typeof setTimeout>
	generation: number
}

export type RPCMessageSender = (message: OverlayTransportMessage) => void

/** Owns request timeout, reconnect generations, and pending RPC cleanup. */
export class PendingRPCRegistry {
	private readonly pending = new Map<string, PendingCall>()
	private nextRequest = 0
	private generation = 0

	constructor(
		private readonly send: RPCMessageSender,
		private readonly timeoutMs: number,
	) {}

	get connectionGeneration(): number {
		return this.generation
	}

	call<T = unknown>(name: string, ...args: unknown[]): Promise<T> {
		const requestId = `overlay-${Date.now()}-${this.nextRequest++}`
		return new Promise<T>((resolve, reject) => {
			const generation = this.generation
			const timeout = setTimeout(() => {
				const call = this.pending.get(requestId)
				if (!call || call.generation !== generation) return
				this.pending.delete(requestId)
				reject(new Error(`Overlay RPC timed out: ${name}.`))
			}, this.timeoutMs)
			this.pending.set(requestId, {
				resolve: resolve as (value: unknown) => void,
				reject,
				timeout,
				generation,
			})
			try {
				this.send({ requestId, name, args })
			} catch (error) {
				this.pending.delete(requestId)
				clearTimeout(timeout)
				reject(error)
			}
		})
	}

	/** Handles any response ID, including late responses from old generations. */
	handleResponse(message: OverlayTransportMessage): void {
		const responseId = message.responseId
		if (!responseId) return
		const call = this.pending.get(responseId)
		if (!call || call.generation !== this.generation) return
		this.pending.delete(responseId)
		clearTimeout(call.timeout)
		if (message.failed) call.reject(message.failed)
		else call.resolve(message.result)
	}

	/** Invalidates every request when the transport disconnects or stops. */
	reset(reason: Error): void {
		this.generation++
		this.rejectAll(reason)
	}

	rejectAll(reason: Error): void {
		for (const call of this.pending.values()) {
			clearTimeout(call.timeout)
			call.reject(reason)
		}
		this.pending.clear()
	}
}
