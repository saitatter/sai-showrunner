import { describe, expect, it } from "vitest"
import {
	SHADER_GRAPH_STARTERS,
	applyCompiledShaderGraph,
	collectShaderUniformBindings,
	createDefaultShaderGraph,
	createShaderGraphStarter,
	normalizeShaderGraph,
	hasLegacyCustomShaderWithoutGraph,
	persistShaderGraph,
	type ShaderLayerGraphConfig,
} from "./shader-graph-state"
import { compileShaderGraph } from "./shader-nodes"
import { resolveShaderUniformBindings, type ShaderUniformBindingMap } from "showrunner-plugin-overlays-shared"

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
		const bindings: ShaderUniformBindingMap = { u_amount: { source: "config", path: "intensity" } }

		applyCompiledShaderGraph(config, graph, "new glsl", { u_amount: 0.5 }, bindings)

		expect(config.preset).toBe("custom")
		expect(config.customFragmentShader).toBe("new glsl")
		expect(config.shaderGraph).toEqual(graph)
		expect(config.shaderUniforms).toEqual({ u_amount: 0.5 })
		expect(config.shaderUniformBindings).toEqual(bindings)
	})

	it("preserves manual shader graph frames during clone and normalize", () => {
		const graph = createDefaultShaderGraph()
		graph.frames = [{
			id: "frame-a",
			title: "Terrain",
			color: "#7c4dff",
			x: 20,
			y: 30,
			width: 420,
			height: 240,
			nodeIds: ["uv", "missing"],
		}]

		const normalized = normalizeShaderGraph(graph)

		expect(normalized.frames).toEqual([{
			id: "frame-a",
			title: "Terrain",
			color: "#7c4dff",
			x: 20,
			y: 30,
			width: 420,
			height: 240,
			nodeIds: ["uv"],
		}])
	})

	it("collects runtime bindings from uniform parameter nodes", () => {
		const graph = {
			nodes: [
				{ id: "amount", defId: "uniform_float", x: 0, y: 0, inputDefaults: { name: "amount", bindingSource: "config", bindingPath: "intensity" } },
				{ id: "meter", defId: "uniform_vec3", x: 0, y: 120, inputDefaults: { name: "meter_color", bindingSource: "state", bindingPlugin: "audio", bindingState: "meter", bindingPath: "color" } },
				{ id: "ignored", defId: "uniform_vec2", x: 0, y: 240, inputDefaults: { name: "ignored", bindingSource: "state", bindingPlugin: "audio" } },
			],
			wires: [],
		}

		expect(collectShaderUniformBindings(graph)).toEqual({
			u_amount: { source: "config", path: "intensity" },
			u_meter_color: { source: "state", plugin: "audio", state: "meter", path: "color" },
		})
	})

	it("resolves shader uniform bindings over default values", () => {
		const resolved = resolveShaderUniformBindings(
			{ u_amount: 0.5, u_color: [0, 0, 0] },
			{
				u_amount: { source: "config", path: "intensity" },
				u_color: { source: "state", plugin: "audio", state: "meter", path: "color" },
			},
			{
				config: { intensity: "0.8" },
				states: { audio: { meter: { color: [0.1, 0.2, 0.3] } } },
			}
		)

		expect(resolved).toEqual({ u_amount: 0.8, u_color: [0.1, 0.2, 0.3] })
	})

	it("detects legacy custom GLSL that has no graph to restore", () => {
		expect(hasLegacyCustomShaderWithoutGraph({ preset: "custom", customFragmentShader: "void main() {}" })).toBe(true)
		expect(hasLegacyCustomShaderWithoutGraph({ preset: "custom", customFragmentShader: "void main() {}", shaderGraph: createDefaultShaderGraph() })).toBe(false)
	})

	it("creates compiling shader starter graphs", () => {
		expect(SHADER_GRAPH_STARTERS.map((starter) => starter.id)).toEqual([
			"procedural-terrain",
			"nebula",
			"audio-reactive",
			"energy-field",
		])

		for (const starter of SHADER_GRAPH_STARTERS) {
			const graph = createShaderGraphStarter(starter.id)
			const result = compileShaderGraph(graph)
			expect(result.errors, starter.name).toEqual([])
			expect(result.glsl, starter.name).toContain("gl_FragColor")
		}
	})
})
