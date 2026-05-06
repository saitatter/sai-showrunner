import { describe, expect, it } from "vitest"
import {
	applyCompiledShaderGraph,
	createDefaultShaderGraph,
	hasLegacyCustomShaderWithoutGraph,
	persistShaderGraph,
	type ShaderLayerGraphConfig,
} from "./shader-graph-state"
import { compileShaderGraph } from "./shader-nodes"

describe("shader graph config state", () => {
	it("creates a visible default gradient graph", () => {
		const graph = createDefaultShaderGraph()
		const result = compileShaderGraph(graph)

		expect(graph.nodes.map((node) => node.defId)).toEqual([
			"uv",
			"vec2_split",
			"accent_color",
			"secondary_color",
			"mix_color",
			"fragment_output",
		])
		expect(graph.wires.length).toBe(5)
		expect(result.errors).toEqual([])
		expect(result.glsl).toContain("mix(")
		expect(result.glsl).toContain("u_accent")
		expect(result.glsl).toContain("u_secondary")
	})

	it("persists a shader graph without changing the current shader source", () => {
		const config: ShaderLayerGraphConfig = { preset: "custom", customFragmentShader: "old glsl" }
		const graph = createDefaultShaderGraph()

		persistShaderGraph(config, graph)

		expect(config.customFragmentShader).toBe("old glsl")
		expect(config.shaderGraph).toEqual(graph)
	})

	it("updates the custom shader only after a successful graph compile", () => {
		const config: ShaderLayerGraphConfig = { preset: "aurora", customFragmentShader: "old glsl" }
		const graph = createDefaultShaderGraph()

		applyCompiledShaderGraph(config, graph, "new glsl", { u_amount: 0.5 })

		expect(config.preset).toBe("custom")
		expect(config.customFragmentShader).toBe("new glsl")
		expect(config.shaderGraph).toEqual(graph)
		expect(config.shaderUniforms).toEqual({ u_amount: 0.5 })
	})

	it("detects legacy custom GLSL that has no graph to restore", () => {
		expect(hasLegacyCustomShaderWithoutGraph({ preset: "custom", customFragmentShader: "void main() {}" })).toBe(true)
		expect(hasLegacyCustomShaderWithoutGraph({ preset: "custom", customFragmentShader: "void main() {}", shaderGraph: createDefaultShaderGraph() })).toBe(false)
	})
})
