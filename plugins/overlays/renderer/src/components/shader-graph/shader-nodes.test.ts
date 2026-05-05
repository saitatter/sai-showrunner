import { describe, expect, it } from "vitest"
import {
	areShaderTypesCompatible,
	collectShaderUniformDefaults,
	compileShaderGraph,
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
