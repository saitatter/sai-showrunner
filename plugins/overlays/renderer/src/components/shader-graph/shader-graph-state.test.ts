import { describe, expect, it } from "vitest"
import {
	applyCompiledShaderGraph,
	createDefaultShaderGraph,
	hasLegacyCustomShaderWithoutGraph,
	persistShaderGraph,
	type ShaderLayerGraphConfig,
} from "./shader-graph-state"

describe("shader graph config state", () => {
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

		applyCompiledShaderGraph(config, graph, "new glsl")

		expect(config.preset).toBe("custom")
		expect(config.customFragmentShader).toBe("new glsl")
		expect(config.shaderGraph).toEqual(graph)
	})

	it("detects legacy custom GLSL that has no graph to restore", () => {
		expect(hasLegacyCustomShaderWithoutGraph({ preset: "custom", customFragmentShader: "void main() {}" })).toBe(true)
		expect(hasLegacyCustomShaderWithoutGraph({ preset: "custom", customFragmentShader: "void main() {}", shaderGraph: createDefaultShaderGraph() })).toBe(false)
	})
})
