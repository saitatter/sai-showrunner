import { describe, expect, it } from "vitest"
import {
	findNearestGraphPort,
	evaluateGraphRuntime,
	graphBezierPath,
	graphDistance,
	graphPointFromClient,
	graphPortPositionKey,
	graphSkinStyle,
	graphValidationFromIssues,
	graphWireId,
	oppositeGraphPortKind,
	resolveGraphWireEndpoints,
} from "./graph"

describe("graph geometry helpers", () => {
	it("builds stable port position keys", () => {
		expect(graphPortPositionKey("node", "value", "out")).toBe("out:node:value")
	})

	it("resolves graph wire direction from either end", () => {
		expect(oppositeGraphPortKind("out")).toBe("in")
		expect(resolveGraphWireEndpoints(
			{ fromNode: "source", fromPort: "value", fromKind: "out" },
			{ nodeId: "target", portKey: "input", kind: "in" }
		)).toEqual({ fromNode: "source", fromPort: "value", toNode: "target", toPort: "input" })
		expect(resolveGraphWireEndpoints(
			{ fromNode: "target", fromPort: "input", fromKind: "in" },
			{ nodeId: "source", portKey: "value", kind: "out" }
		)).toEqual({ fromNode: "source", fromPort: "value", toNode: "target", toPort: "input" })
		expect(graphWireId({ fromNode: "source", fromPort: "value", toNode: "target", toPort: "input" })).toBe("source:value->target:input")
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

	it("finds the nearest valid snap port", () => {
		const nearest = findNearestGraphPort(
			{ x: 10, y: 10 },
			[
				{ nodeId: "far", portKey: "value", kind: "in", position: { x: 80, y: 80 } },
				{ nodeId: "invalid", portKey: "value", kind: "in", position: { x: 9, y: 9 } },
				{ nodeId: "near", portKey: "value", kind: "in", position: { x: 14, y: 10 } },
			],
			20,
			(candidate) => candidate.nodeId !== "invalid"
		)

		expect(graphDistance({ x: 0, y: 0 }, { x: 3, y: 4 })).toBe(5)
		expect(nearest?.nodeId).toBe("near")
	})

	it("normalizes validation issues and skin tokens", () => {
		expect(graphValidationFromIssues([{ severity: "warning", message: "heads up" }])).toEqual({ valid: true })
		expect(graphValidationFromIssues([{ severity: "error", message: "broken", code: "bad" }])).toEqual({
			valid: false,
			message: "broken",
			code: "bad",
		})
		expect(graphSkinStyle({
			canvasBackground: "#000",
			panelBackground: "#111",
			panelBorder: "#222",
			nodeBackground: "#333",
			nodeBorder: "#444",
			nodeSelected: "#555",
			wireDefault: "#666",
			wireInvalid: "#777",
			textMuted: "#888",
		})["--graph-node-selected"]).toBe("#555")
	})

	it("evaluates graph runtimes while preserving the last good output", () => {
		const adapter = {
			evaluate: (graph: { ok: boolean; output?: string }) => graph.ok
				? { output: graph.output, issues: [] }
				: { issues: [{ severity: "error" as const, message: "compile failed" }] },
		}

		const good = evaluateGraphRuntime(adapter, { ok: true, output: "new glsl" }, "old glsl")
		expect(good.ok).toBe(true)
		expect(good.lastGoodOutput).toBe("new glsl")

		const failed = evaluateGraphRuntime(adapter, { ok: false }, good.lastGoodOutput)
		expect(failed.ok).toBe(false)
		expect(failed.errorMessages).toEqual(["compile failed"])
		expect(failed.lastGoodOutput).toBe("new glsl")
	})
})
