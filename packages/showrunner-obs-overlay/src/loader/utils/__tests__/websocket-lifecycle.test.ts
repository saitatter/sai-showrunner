import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import { BrowserOverlaySocket } from "../websocket"

class FakeSocket extends EventTarget {
  static OPEN = 1
  static instances: FakeSocket[] = []
  readyState = 0
  bufferedAmount = 0
  closeCode?: number
  sent: string[] = []
  constructor(public url: string) { super(); FakeSocket.instances.push(this) }
  open() { this.readyState = 1; this.dispatchEvent(new Event("open")) }
  close(code?: number) { this.closeCode = code; this.readyState = 3; this.dispatchEvent(new Event("close")) }
  send(message: string) { this.sent.push(message) }
}

describe("production browser overlay connection", () => {
  beforeEach(() => {
    vi.useFakeTimers()
    FakeSocket.instances = []
    vi.stubGlobal("WebSocket", FakeSocket)
    vi.stubGlobal("window", { location: { host: "localhost" }, setTimeout, clearTimeout })
  })
  afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals() })

  it("expires a stalled handshake and cancels all owned timers on close", async () => {
    const transport = new BrowserOverlaySocket("test")
    const connection = transport.connect()
    const rejected = expect(connection).rejects.toThrow("timed out")
    await vi.advanceTimersByTimeAsync(20000)
    await rejected
    expect(FakeSocket.instances[0].readyState).toBe(3)
    await transport.close()
    expect(vi.getTimerCount()).toBe(0)
  })

  it("uses secure WebSockets for HTTPS and rejects disconnected or saturated sends", async () => {
    vi.stubGlobal("window", {location:{host:"localhost",protocol:"https:"},setTimeout,clearTimeout})
    const transport = new BrowserOverlaySocket("test")
    expect(() => transport.send({requestId:"one",name:"read",args:[]})).toThrow("closed")
    const connection = transport.connect()
    const socket = FakeSocket.instances[0]
    expect(socket.url).toBe("wss://localhost/overlays/test/socket")
    socket.open()
    await connection
    expect(vi.getTimerCount()).toBe(0)
    socket.bufferedAmount = 1024 * 1024 + 1
    expect(() => transport.send({requestId:"one",name:"read",args:[]})).toThrow("buffer")
    expect(socket.closeCode).toBe(1008)
    expect(socket.sent).toHaveLength(0)
    await transport.close()
  })

  it.each([
    ["malformed", "{invalid", 1007],
    ["oversized", "x".repeat(1024 * 1024 + 1), 1009],
    ["binary", new Uint8Array([1]), 1003],
  ])("rejects %s inbound traffic before notifying consumers", async (_name, data, code) => {
    const transport = new BrowserOverlaySocket("test")
    const listener = vi.fn()
    transport.onMessage(listener)
    const connection = transport.connect()
    const socket = FakeSocket.instances[0]
    socket.open()
    await connection
    const event = new Event("message")
    Object.defineProperty(event, "data", {value:data})
    socket.dispatchEvent(event)
    expect(socket.closeCode).toBe(code)
    expect(listener).not.toHaveBeenCalled()
    await transport.close()
    expect(vi.getTimerCount()).toBe(0)
  })

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
