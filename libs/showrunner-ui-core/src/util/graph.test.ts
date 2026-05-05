import { describe, expect, it } from "vitest"
import { graphBezierPath, graphPointFromClient, graphPortPositionKey } from "./graph"

describe("graph geometry helpers", () => {
	it("builds stable port position keys", () => {
		expect(graphPortPositionKey("node", "value", "out")).toBe("out:node:value")
	})

	it("builds cubic bezier wire paths", () => {
		expect(graphBezierPath(10, 20, 110, 40)).toBe("M 10 20 C 70 20, 50 40, 110 40")
		expect(graphBezierPath(10, 20, 40, 40, { minControl: 50 })).toBe("M 10 20 C 60 20, -10 40, 40 40")
	})

	it("converts client positions into graph space", () => {
		const surface = {
			getBoundingClientRect: () => ({ left: 100, top: 50 }),
		} as HTMLElement

		expect(graphPointFromClient(surface, 140, 90, 2)).toEqual({ x: 20, y: 20 })
	})
})
