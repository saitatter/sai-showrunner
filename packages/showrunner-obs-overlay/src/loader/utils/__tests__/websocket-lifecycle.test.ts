import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import { BrowserOverlaySocket } from "../websocket"

class FakeSocket extends EventTarget {
  static OPEN = 1
  static instances: FakeSocket[] = []
  readyState = 0
  constructor(public url: string) { super(); FakeSocket.instances.push(this) }
  open() { this.readyState = 1; this.dispatchEvent(new Event("open")) }
  close() { this.readyState = 3; this.dispatchEvent(new Event("close")) }
  send(_message: string) {}
}

describe("production browser overlay connection", () => {
  beforeEach(() => {
    vi.useFakeTimers()
    FakeSocket.instances = []
    vi.stubGlobal("WebSocket", FakeSocket)
    vi.stubGlobal("window", { location: { host: "localhost" }, setTimeout, clearTimeout })
  })
  afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals() })

  it("shares an in-flight connection and retains connected status on repeated connect", async () => {
    const transport = new BrowserOverlaySocket("test")
    const statuses: string[] = []
    transport.onStatus(s => statuses.push(s))
    const first = transport.connect()
    const second = transport.connect()
    expect(first).toBe(second)
    expect(FakeSocket.instances).toHaveLength(1)
    FakeSocket.instances[0].open()
    await first
    await transport.connect()
    expect(statuses.at(-1)).toBe("connected")
    await transport.close()
  })

  it("reconnects once after disconnect and stops retrying after explicit close", async () => {
    const transport = new BrowserOverlaySocket("test")
    const first = transport.connect()
    FakeSocket.instances[0].open()
    await first
    FakeSocket.instances[0].close()
    FakeSocket.instances[0].close()
    await vi.advanceTimersByTimeAsync(1000)
    expect(FakeSocket.instances).toHaveLength(2)
    FakeSocket.instances[1].open()
    await transport.connect()
    FakeSocket.instances[1].close()
    await transport.close()
    await vi.advanceTimersByTimeAsync(3000)
    expect(FakeSocket.instances).toHaveLength(2)
  })

  it("settles close-before-open and ignores late events from the previous socket", async () => {
    const transport = new BrowserOverlaySocket("test")
    const first = transport.connect()
    const rejected = expect(first).rejects.toThrow("closed before opening")
    await transport.close()
    await rejected
    const second = transport.connect()
    FakeSocket.instances[1].open()
    await second
    FakeSocket.instances[0].open()
    FakeSocket.instances[0].close()
    await transport.connect()
    await vi.advanceTimersByTimeAsync(1000)
    expect(FakeSocket.instances).toHaveLength(2)
    await transport.close()
  })
})
