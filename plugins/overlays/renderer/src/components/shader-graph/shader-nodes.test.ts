import { describe, expect, it } from "vitest"
import {
	areShaderTypesCompatible,
	collectShaderUniformDefaults,
	compileShaderGraph,
	createShaderNodePreviewGraph,
	validateShaderGraph,
	wouldCreateShaderGraphCycle,
	type ShaderGraph,
} from "./shader-nodes"

describe("shader graph compiler", () => {
	it("compiles a valid output graph", () => {
		const result = compileShaderGraph({
			nodes: [{ id: "output", defId: "fragment_output", x: 0, y: 0 }],
			wires: [],
			outputNodeId: "output",
		})

		expect(result.errors).toEqual([])
		expect(result.glsl).toContain("gl_FragColor")
	})

	it("reports a missing fragment output", () => {
		const errors = validateShaderGraph({
			nodes: [{ id: "uv", defId: "uv", x: 0, y: 0 }],
			wires: [],
		})

		expect(errors).toContain("Shader graph is missing a Fragment Output node.")
	})

	it("reports cycles before generating GLSL", () => {
		const graph: ShaderGraph = {
			nodes: [
				{ id: "a", defId: "add", x: 0, y: 0 },
				{ id: "b", defId: "add", x: 200, y: 0 },
				{ id: "output", defId: "fragment_output", x: 400, y: 0 },
			],
			wires: [
				{ id: "a:result->b:a", fromNode: "a", fromPort: "result", toNode: "b", toPort: "a" },
				{ id: "b:result->a:a", fromNode: "b", fromPort: "result", toNode: "a", toPort: "a" },
			],
			outputNodeId: "output",
		}
		const result = compileShaderGraph(graph)

		expect(result.glsl).toBe("")
		expect(result.errors).toContain("Shader graph contains a cycle.")
		expect(wouldCreateShaderGraphCycle({ ...graph, wires: [graph.wires[0]] }, "b", "a")).toBe(true)
	})

	it("reports incompatible wire types", () => {
		const graph: ShaderGraph = {
			nodes: [
				{ id: "uv", defId: "uv", x: 0, y: 0 },
				{ id: "output", defId: "fragment_output", x: 200, y: 0 },
			],
			wires: [
				{ id: "uv:uv->output:color", fromNode: "uv", fromPort: "uv", toNode: "output", toPort: "color" },
			],
			outputNodeId: "output",
		}

		expect(areShaderTypesCompatible("vec2", "vec3")).toBe(false)
		expect(validateShaderGraph(graph)).toContain("Wire uv:uv->output:color connects incompatible types: vec2 -> vec3.")
	})

	it("compiles editable constant node defaults", () => {
		const result = compileShaderGraph({
			nodes: [
				{ id: "color", defId: "vec3_const", x: 0, y: 0, inputDefaults: { value: "vec3(0.100, 0.200, 0.300)" } },
				{ id: "output", defId: "fragment_output", x: 220, y: 0 },
			],
			wires: [
				{ id: "color:value->output:color", fromNode: "color", fromPort: "value", toNode: "output", toPort: "color" },
			],
			outputNodeId: "output",
		})

		expect(result.errors).toEqual([])
		expect(result.glsl).toContain("= vec3(0.100, 0.200, 0.300);")
	})

	it("compiles custom uniform parameter nodes", () => {
		const graph: ShaderGraph = {
			nodes: [
				{ id: "color", defId: "uniform_vec3", x: 0, y: 0, inputDefaults: { name: "alert_color", value: "vec3(0.250, 0.500, 0.750)" } },
				{ id: "output", defId: "fragment_output", x: 220, y: 0 },
			],
			wires: [
				{ id: "color:value->output:color", fromNode: "color", fromPort: "value", toNode: "output", toPort: "color" },
			],
			outputNodeId: "output",
		}

		const result = compileShaderGraph(graph)

		expect(result.errors).toEqual([])
		expect(result.glsl).toContain("uniform vec3 u_alert_color;")
		expect(result.glsl).toContain("= u_alert_color;")
		expect(collectShaderUniformDefaults(graph)).toEqual({ u_alert_color: [0.25, 0.5, 0.75] })
	})

	it("compiles procedural utility nodes", () => {
		const result = compileShaderGraph({
			nodes: [
				{ id: "uv", defId: "uv", x: 0, y: 0 },
				{ id: "time", defId: "time", x: 0, y: 120 },
				{ id: "rotate", defId: "rotate_uv", x: 220, y: 0, inputDefaults: { angle: "0.25" } },
				{ id: "tile", defId: "tile_uv", x: 440, y: 0, inputDefaults: { scale: "4.0" } },
				{ id: "split", defId: "vec2_split", x: 660, y: 0 },
				{ id: "wave", defId: "wave", x: 880, y: 0, inputDefaults: { frequency: "12.0", speed: "2.0" } },
				{ id: "gradient", defId: "gradient_color", x: 1100, y: 0 },
				{ id: "output", defId: "fragment_output", x: 1320, y: 0 },
			],
			wires: [
				{ id: "uv:uv->rotate:uv", fromNode: "uv", fromPort: "uv", toNode: "rotate", toPort: "uv" },
				{ id: "rotate:uv->tile:uv", fromNode: "rotate", fromPort: "uv", toNode: "tile", toPort: "uv" },
				{ id: "tile:uv->split:v", fromNode: "tile", fromPort: "uv", toNode: "split", toPort: "v" },
				{ id: "split:x->wave:x", fromNode: "split", fromPort: "x", toNode: "wave", toPort: "x" },
				{ id: "time:t->wave:time", fromNode: "time", fromPort: "t", toNode: "wave", toPort: "time" },
				{ id: "wave:result->gradient:factor", fromNode: "wave", fromPort: "result", toNode: "gradient", toPort: "factor" },
				{ id: "gradient:color->output:color", fromNode: "gradient", fromPort: "color", toNode: "output", toPort: "color" },
			],
			outputNodeId: "output",
		})

		expect(result.errors).toEqual([])
		expect(result.glsl).toContain("mat2(")
		expect(result.glsl).toContain("fract(")
		expect(result.glsl).toContain("0.5 + 0.5 * sin(")
		expect(result.glsl).toContain("clamp(")
		expect(result.glsl).toContain("mix(")
	})

	it("creates preview graphs for node outputs", () => {
		const graph: ShaderGraph = {
			nodes: [
				{ id: "uv", defId: "uv", x: 0, y: 0 },
				{ id: "split", defId: "vec2_split", x: 220, y: 0 },
				{ id: "wave", defId: "wave", x: 440, y: 0 },
				{ id: "gradient", defId: "gradient_color", x: 660, y: 0 },
				{ id: "output", defId: "fragment_output", x: 880, y: 0 },
			],
			wires: [
				{ id: "uv:uv->split:v", fromNode: "uv", fromPort: "uv", toNode: "split", toPort: "v" },
				{ id: "split:x->wave:x", fromNode: "split", fromPort: "x", toNode: "wave", toPort: "x" },
				{ id: "wave:result->gradient:factor", fromNode: "wave", fromPort: "result", toNode: "gradient", toPort: "factor" },
				{ id: "gradient:color->output:color", fromNode: "gradient", fromPort: "color", toNode: "output", toPort: "color" },
			],
			outputNodeId: "output",
		}

		const floatPreview = createShaderNodePreviewGraph(graph, "wave")
		const vec2Preview = createShaderNodePreviewGraph(graph, "uv")
		const colorPreview = createShaderNodePreviewGraph(graph, "gradient")

		expect(floatPreview?.outputNodeId).toBe("__preview_wave_output")
		expect(vec2Preview?.nodes.some((node) => node.defId === "vec2_split")).toBe(true)
		expect(colorPreview?.wires).toContainEqual({
			id: "gradient:color->__preview_gradient_output:color",
			fromNode: "gradient",
			fromPort: "color",
			toNode: "__preview_gradient_output",
			toPort: "color",
		})
		expect(compileShaderGraph(floatPreview!).errors).toEqual([])
		expect(compileShaderGraph(vec2Preview!).errors).toEqual([])
		expect(compileShaderGraph(colorPreview!).errors).toEqual([])
	})

	it("reports duplicate custom uniform names", () => {
		const errors = validateShaderGraph({
			nodes: [
				{ id: "amountA", defId: "uniform_float", x: 0, y: 0, inputDefaults: { name: "amount" } },
				{ id: "amountB", defId: "uniform_float", x: 0, y: 120, inputDefaults: { name: "amount" } },
				{ id: "output", defId: "fragment_output", x: 220, y: 0 },
			],
			wires: [],
			outputNodeId: "output",
		})

		expect(errors).toContain('Uniform name "u_amount" is used by multiple parameter nodes.')
	})
})
