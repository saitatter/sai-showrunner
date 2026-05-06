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

	it("compiles procedural noise nodes", () => {
		const result = compileShaderGraph({
			nodes: [
				{ id: "uv", defId: "uv", x: 0, y: 0 },
				{ id: "warp", defId: "domain_warp", x: 220, y: 0, inputDefaults: { scale: "2.5", strength: "0.35" } },
				{ id: "fbm", defId: "fbm_noise", x: 440, y: 0, inputDefaults: { octaves: "6.0" } },
				{ id: "value", defId: "value_noise", x: 440, y: 140 },
				{ id: "perlin", defId: "perlin_noise", x: 440, y: 280 },
				{ id: "voronoi", defId: "voronoi_noise", x: 440, y: 420 },
				{ id: "color", defId: "gradient_color", x: 660, y: 0 },
				{ id: "output", defId: "fragment_output", x: 880, y: 0 },
			],
			wires: [
				{ id: "uv:uv->warp:uv", fromNode: "uv", fromPort: "uv", toNode: "warp", toPort: "uv" },
				{ id: "warp:uv->fbm:uv", fromNode: "warp", fromPort: "uv", toNode: "fbm", toPort: "uv" },
				{ id: "uv:uv->value:uv", fromNode: "uv", fromPort: "uv", toNode: "value", toPort: "uv" },
				{ id: "uv:uv->perlin:uv", fromNode: "uv", fromPort: "uv", toNode: "perlin", toPort: "uv" },
				{ id: "uv:uv->voronoi:uv", fromNode: "uv", fromPort: "uv", toNode: "voronoi", toPort: "uv" },
				{ id: "fbm:value->color:factor", fromNode: "fbm", fromPort: "value", toNode: "color", toPort: "factor" },
				{ id: "color:color->output:color", fromNode: "color", fromPort: "color", toNode: "output", toPort: "color" },
			],
			outputNodeId: "output",
		})

		expect(result.errors).toEqual([])
		expect(result.glsl).toContain("float sr_value_noise")
		expect(result.glsl).toContain("float sr_perlin_noise")
		expect(result.glsl).toContain("float sr_fbm")
		expect(result.glsl).toContain("float sr_voronoi")
		expect(result.glsl).toContain("vec2 sr_domain_warp")
		expect(result.glsl).toContain("sr_domain_warp(")
		expect(result.glsl).toContain("sr_fbm(")
	})

	it("compiles terrain pipeline nodes", () => {
		const result = compileShaderGraph({
			nodes: [
				{ id: "uv", defId: "uv", x: 0, y: 0 },
				{ id: "base", defId: "fbm_noise", x: 220, y: 0 },
				{ id: "detail", defId: "value_noise", x: 220, y: 140, inputDefaults: { scale: "18.0" } },
				{ id: "height", defId: "terrain_height", x: 440, y: 0 },
				{ id: "remap", defId: "height_remap", x: 660, y: 0, inputDefaults: { power: "1.4" } },
				{ id: "normal", defId: "normal_from_height", x: 880, y: 0 },
				{ id: "slope", defId: "slope_mask", x: 1100, y: 0 },
				{ id: "curvature", defId: "curvature_mask", x: 1100, y: 160 },
				{ id: "erosion", defId: "thermal_erosion", x: 1320, y: 0 },
				{ id: "color", defId: "gradient_color", x: 1540, y: 0 },
				{ id: "output", defId: "fragment_output", x: 1760, y: 0 },
			],
			wires: [
				{ id: "uv:uv->base:uv", fromNode: "uv", fromPort: "uv", toNode: "base", toPort: "uv" },
				{ id: "uv:uv->detail:uv", fromNode: "uv", fromPort: "uv", toNode: "detail", toPort: "uv" },
				{ id: "base:value->height:base", fromNode: "base", fromPort: "value", toNode: "height", toPort: "base" },
				{ id: "detail:value->height:detail", fromNode: "detail", fromPort: "value", toNode: "height", toPort: "detail" },
				{ id: "height:height->remap:height", fromNode: "height", fromPort: "height", toNode: "remap", toPort: "height" },
				{ id: "remap:height->normal:center", fromNode: "remap", fromPort: "height", toNode: "normal", toPort: "center" },
				{ id: "remap:height->normal:right", fromNode: "remap", fromPort: "height", toNode: "normal", toPort: "right" },
				{ id: "remap:height->normal:up", fromNode: "remap", fromPort: "height", toNode: "normal", toPort: "up" },
				{ id: "normal:normal->slope:normal", fromNode: "normal", fromPort: "normal", toNode: "slope", toPort: "normal" },
				{ id: "remap:height->curvature:center", fromNode: "remap", fromPort: "height", toNode: "curvature", toPort: "center" },
				{ id: "slope:mask->erosion:slope", fromNode: "slope", fromPort: "mask", toNode: "erosion", toPort: "slope" },
				{ id: "remap:height->erosion:height", fromNode: "remap", fromPort: "height", toNode: "erosion", toPort: "height" },
				{ id: "erosion:height->color:factor", fromNode: "erosion", fromPort: "height", toNode: "color", toPort: "factor" },
				{ id: "color:color->output:color", fromNode: "color", fromPort: "color", toNode: "output", toPort: "color" },
			],
			outputNodeId: "output",
		})

		expect(result.errors).toEqual([])
		expect(result.glsl).toContain("pow(clamp(")
		expect(result.glsl).toContain("normalize(vec3(")
		expect(result.glsl).toContain("1.0 - clamp(")
		expect(result.glsl).toContain("4.0 *")
		expect(result.glsl).toContain("max(")
	})

	it("compiles color ramp and biome nodes", () => {
		const result = compileShaderGraph({
			nodes: [
				{ id: "height", defId: "float_const", x: 0, y: 0, inputDefaults: { value: "0.66" } },
				{ id: "slope", defId: "float_const", x: 0, y: 120, inputDefaults: { value: "0.35" } },
				{ id: "ramp", defId: "color_ramp", x: 220, y: 0 },
				{ id: "mask", defId: "biome_mask", x: 220, y: 160 },
				{ id: "bands", defId: "altitude_bands", x: 440, y: 0 },
				{ id: "blend", defId: "mask_blend_color", x: 660, y: 0 },
				{ id: "output", defId: "fragment_output", x: 880, y: 0 },
			],
			wires: [
				{ id: "height:value->ramp:factor", fromNode: "height", fromPort: "value", toNode: "ramp", toPort: "factor" },
				{ id: "height:value->mask:height", fromNode: "height", fromPort: "value", toNode: "mask", toPort: "height" },
				{ id: "slope:value->mask:slope", fromNode: "slope", fromPort: "value", toNode: "mask", toPort: "slope" },
				{ id: "height:value->bands:height", fromNode: "height", fromPort: "value", toNode: "bands", toPort: "height" },
				{ id: "ramp:color->blend:base", fromNode: "ramp", fromPort: "color", toNode: "blend", toPort: "base" },
				{ id: "bands:color->blend:detail", fromNode: "bands", fromPort: "color", toNode: "blend", toPort: "detail" },
				{ id: "mask:mask->blend:mask", fromNode: "mask", fromPort: "mask", toNode: "blend", toPort: "mask" },
				{ id: "blend:color->output:color", fromNode: "blend", fromPort: "color", toNode: "output", toPort: "color" },
			],
			outputNodeId: "output",
		})

		expect(result.errors).toEqual([])
		expect(result.glsl).toContain("smoothstep(")
		expect(result.glsl).toContain("grassMask")
		expect(result.glsl).toContain("rockMask")
		expect(result.glsl).toContain("snowMask")
		expect(result.glsl).toContain("mix(")
	})

	it("compiles lighting nodes", () => {
		const result = compileShaderGraph({
			nodes: [
				{ id: "color", defId: "vec3_const", x: 0, y: 0, inputDefaults: { value: "vec3(0.25, 0.45, 0.18)" } },
				{ id: "normal", defId: "normal_from_height", x: 0, y: 140 },
				{ id: "sun", defId: "sun_direction", x: 220, y: 0 },
				{ id: "diffuse", defId: "diffuse_lighting", x: 440, y: 0 },
				{ id: "specular", defId: "specular_lighting", x: 440, y: 180 },
				{ id: "shadow", defId: "simple_shadow", x: 660, y: 180 },
				{ id: "ao", defId: "ambient_occlusion", x: 660, y: 320 },
				{ id: "ambient", defId: "ambient_light", x: 660, y: 0 },
				{ id: "depth", defId: "float_const", x: 660, y: 460, inputDefaults: { value: "0.6" } },
				{ id: "fog", defId: "fog", x: 880, y: 0 },
				{ id: "output", defId: "fragment_output", x: 1100, y: 0 },
			],
			wires: [
				{ id: "color:value->diffuse:color", fromNode: "color", fromPort: "value", toNode: "diffuse", toPort: "color" },
				{ id: "normal:normal->diffuse:normal", fromNode: "normal", fromPort: "normal", toNode: "diffuse", toPort: "normal" },
				{ id: "sun:direction->diffuse:lightDir", fromNode: "sun", fromPort: "direction", toNode: "diffuse", toPort: "lightDir" },
				{ id: "normal:normal->specular:normal", fromNode: "normal", fromPort: "normal", toNode: "specular", toPort: "normal" },
				{ id: "sun:direction->specular:lightDir", fromNode: "sun", fromPort: "direction", toNode: "specular", toPort: "lightDir" },
				{ id: "normal:normal->shadow:normal", fromNode: "normal", fromPort: "normal", toNode: "shadow", toPort: "normal" },
				{ id: "sun:direction->shadow:lightDir", fromNode: "sun", fromPort: "direction", toNode: "shadow", toPort: "lightDir" },
				{ id: "diffuse:color->ambient:color", fromNode: "diffuse", fromPort: "color", toNode: "ambient", toPort: "color" },
				{ id: "ambient:color->fog:color", fromNode: "ambient", fromPort: "color", toNode: "fog", toPort: "color" },
				{ id: "depth:value->fog:depth", fromNode: "depth", fromPort: "value", toNode: "fog", toPort: "depth" },
				{ id: "fog:color->output:color", fromNode: "fog", fromPort: "color", toNode: "output", toPort: "color" },
			],
			outputNodeId: "output",
		})

		expect(result.errors).toEqual([])
		expect(result.glsl).toContain("cos(")
		expect(result.glsl).toContain("dot(normalize(")
		expect(result.glsl).toContain("pow(max(")
		expect(result.glsl).toContain("exp(-max(")
		expect(result.glsl).toContain("smoothstep(-")
		expect(result.glsl).toContain("0.65")
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
