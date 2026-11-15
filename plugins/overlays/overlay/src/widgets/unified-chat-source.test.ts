import {afterEach, beforeEach, describe, expect, it, vi} from "vitest"
import {decodeUnifiedChat, UnifiedChatFeedSource, UnifiedChatMessage} from "./unified-chat-source"

const row = (id: string, expiresInMs?: number): UnifiedChatMessage => ({id,platform:"twitch",displayName:"Viewer",message:"<script>private()</script>",badges:[],...(expiresInMs === undefined ? {} : {expiresInMs})})
const response = (messages: UnifiedChatMessage[]) => new Response(JSON.stringify({version:1,messages}), {status:200})

describe("unified chat overlay source", () => {
	const sources: UnifiedChatFeedSource[] = []
	beforeEach(() => vi.useFakeTimers())
	afterEach(() => { for (const source of sources.splice(0)) source.stop(); vi.unstubAllGlobals(); vi.useRealTimers() })
	it("replaces snapshots for deletions and clears, expiring locally during an outage", async () => {
		const updates: UnifiedChatMessage[][] = []
		const fetch = vi.fn().mockResolvedValueOnce(response([row("first", 1500),row("second",500)]))
			.mockRejectedValueOnce(new Error("offline")).mockResolvedValue(response([]))
		vi.stubGlobal("fetch", fetch)
		const source = new UnifiedChatFeedSource("overlay/name", "widget?#", rows => updates.push(rows))
		sources.push(source); source.start()
		await vi.advanceTimersByTimeAsync(0)
		expect(fetch.mock.calls[0]?.[0]).toBe("/overlays/overlay%2Fname/chat/widget%3F%23")
		expect(fetch.mock.calls[0]?.[1]).toMatchObject({credentials:"same-origin",cache:"no-store"})
		expect(updates.at(-1)?.map(r=>r.id)).toEqual(["first","second"])
		await vi.advanceTimersByTimeAsync(500)
		expect(updates.at(-1)?.map(r=>r.id)).toEqual(["first"])
		await vi.advanceTimersByTimeAsync(1000)
		expect(updates.at(-1)).toEqual([])
		await vi.advanceTimersByTimeAsync(500)
		expect(fetch).toHaveBeenCalledTimes(3)
		source.stop(); expect(vi.getTimerCount()).toBe(0)
	})
	it("aborts a stopped reader and rejects late snapshots without restarting timers", async () => {
		let resolve!: (value: Response) => void
		const fetch = vi.fn().mockImplementation(() => new Promise<Response>(done => {resolve=done}))
		vi.stubGlobal("fetch", fetch)
		const update = vi.fn()
		const source = new UnifiedChatFeedSource("overlay", "widget", update)
		sources.push(source); source.start(); source.stop()
		expect(fetch.mock.calls[0]?.[1].signal.aborted).toBe(true)
		expect(vi.getTimerCount()).toBe(0)
		resolve(response([row("late")]))
		await vi.advanceTimersByTimeAsync(0)
		expect(update).not.toHaveBeenCalled()
		expect(vi.getTimerCount()).toBe(0)
	})
	it("keeps only the new snapshot after a server deletion", async () => {
		const fetch = vi.fn().mockResolvedValueOnce(response([row("old"),row("kept")]))
			.mockResolvedValueOnce(response([row("kept")])).mockResolvedValue(response([]))
		vi.stubGlobal("fetch", fetch)
		const updates: UnifiedChatMessage[][] = []
		const source = new UnifiedChatFeedSource("overlay", "widget", rows=>updates.push(rows))
		sources.push(source); source.start(); await vi.advanceTimersByTimeAsync(0)
		await vi.advanceTimersByTimeAsync(1000)
		expect(updates.at(-1)?.map(r=>r.id)).toEqual(["kept"])
		await vi.advanceTimersByTimeAsync(1000)
		expect(updates.at(-1)).toEqual([])
	})
	it("rejects unsupported, duplicate, oversized or malformed snapshots", () => {
		for (const value of [{version:2,messages:[]},{version:1,messages:[row("same"),row("same")]},
			{version:1,messages:Array.from({length:201},(_,i)=>row(String(i)))},
			{version:1,messages:[{...row("id"),expiresInMs:Infinity}]},
			{version:1,messages:[{...row("id"),badges:[{}]}]},
			{version:1,messages:[{...row("id"),platform:"unknown"}]}]) {
			expect(()=>decodeUnifiedChat(value)).toThrow()
		}
		expect(decodeUnifiedChat({version:1,messages:[{...row("id"),badges:undefined}]})).toEqual([row("id")])
	})
})
