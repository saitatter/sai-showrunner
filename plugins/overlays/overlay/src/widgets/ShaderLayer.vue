<template>
	<div class="shader-layer" :style="{ opacity: config.opacity, mixBlendMode: config.blendMode }">
		<canvas ref="canvas" class="shader-layer__canvas"></canvas>
		<div v-if="errorMessage" class="shader-layer__fallback">
			<strong>Shader unavailable</strong>
			<span>{{ errorMessage }}</span>
		</div>
		<div v-if="config.text" class="shader-layer__text">{{ config.text }}</div>
	</div>
</template>

<script setup lang="ts">
import { onMounted, onUnmounted, ref, watch } from "vue"
import { declareWidgetOptions } from "showrunner-overlay-core"
import { ShaderRenderer } from "./shader-renderer"

const presets: Record<string, string> = {
	aurora: `
precision mediump float;
uniform vec2 u_resolution;
uniform float u_time;
uniform vec3 u_accent;
uniform vec3 u_secondary;
uniform float u_intensity;
uniform float u_speed;
void main() {
	vec2 uv = gl_FragCoord.xy / u_resolution.xy;
	float wave = sin((uv.x * 7.0 + u_time * u_speed) + sin(uv.y * 5.0 + u_time * 0.35));
	float glow = smoothstep(0.15, 1.0, wave * 0.5 + 0.5) * u_intensity;
	vec3 color = mix(u_secondary, u_accent, uv.y + wave * 0.18);
	gl_FragColor = vec4(color, glow * 0.85);
}
`,
	grid: `
precision mediump float;
uniform vec2 u_resolution;
uniform float u_time;
uniform vec3 u_accent;
uniform vec3 u_secondary;
uniform float u_intensity;
uniform float u_speed;
void main() {
	vec2 uv = gl_FragCoord.xy / u_resolution.xy;
	vec2 grid = abs(fract((uv + vec2(u_time * 0.03 * u_speed, 0.0)) * 18.0) - 0.5);
	float lines = 1.0 - smoothstep(0.0, 0.035, min(grid.x, grid.y));
	float pulse = 0.55 + 0.45 * sin(u_time * u_speed + uv.x * 4.0);
	vec3 color = mix(u_secondary, u_accent, pulse);
	gl_FragColor = vec4(color, lines * u_intensity);
}
`,
	plasma: `
precision mediump float;
uniform vec2 u_resolution;
uniform float u_time;
uniform vec3 u_accent;
uniform vec3 u_secondary;
uniform float u_intensity;
uniform float u_speed;
void main() {
	vec2 uv = (gl_FragCoord.xy * 2.0 - u_resolution.xy) / min(u_resolution.x, u_resolution.y);
	float value = sin(uv.x * 6.0 + u_time * u_speed) + sin(uv.y * 5.0 - u_time * 0.7 * u_speed);
	value += sin((uv.x + uv.y) * 4.0 + u_time * 0.5 * u_speed);
	value = value / 3.0 * 0.5 + 0.5;
	vec3 color = mix(u_secondary, u_accent, value);
	gl_FragColor = vec4(color, value * u_intensity);
}
`,
	nebula: `
precision mediump float;
uniform vec2 u_resolution;
uniform float u_time;
uniform vec3 u_accent;
uniform vec3 u_secondary;
uniform float u_intensity;
uniform float u_speed;
float field(vec2 p) {
	float value = 0.0;
	float scale = 1.0;
	for (int i = 0; i < 4; i++) {
		value += abs(sin(p.x * scale + u_time * 0.15 * u_speed) + cos(p.y * scale - u_time * 0.2 * u_speed)) / scale;
		p = mat2(0.8, -0.6, 0.6, 0.8) * p * 1.35;
		scale *= 1.7;
	}
	return value;
}
void main() {
	vec2 uv = (gl_FragCoord.xy * 2.0 - u_resolution.xy) / min(u_resolution.x, u_resolution.y);
	float cloud = smoothstep(0.9, 2.4, field(uv * 1.4));
	vec3 color = mix(u_secondary * 0.35, u_accent, cloud);
	gl_FragColor = vec4(color, cloud * u_intensity * 0.78);
}
`,
	scanlines: `
precision mediump float;
uniform vec2 u_resolution;
uniform float u_time;
uniform vec3 u_accent;
uniform vec3 u_secondary;
uniform float u_intensity;
uniform float u_speed;
void main() {
	vec2 uv = gl_FragCoord.xy / u_resolution.xy;
	float line = smoothstep(0.48, 0.5, sin((uv.y + u_time * 0.04 * u_speed) * 220.0) * 0.5 + 0.5);
	float sweep = smoothstep(0.02, 0.0, abs(fract(uv.y + u_time * 0.08 * u_speed) - 0.5));
	float edge = smoothstep(0.0, 0.35, uv.x) * smoothstep(1.0, 0.65, uv.x);
	vec3 color = mix(u_secondary, u_accent, uv.x + sweep * 0.4);
	gl_FragColor = vec4(color, (line * 0.2 + sweep * 0.8) * edge * u_intensity);
}
`,
	vortex: `
precision mediump float;
uniform vec2 u_resolution;
uniform float u_time;
uniform vec3 u_accent;
uniform vec3 u_secondary;
uniform float u_intensity;
uniform float u_speed;
void main() {
	vec2 uv = (gl_FragCoord.xy * 2.0 - u_resolution.xy) / min(u_resolution.x, u_resolution.y);
	float radius = length(uv);
	float angle = atan(uv.y, uv.x);
	float swirl = sin(angle * 5.0 + radius * 11.0 - u_time * u_speed * 1.4);
	float ring = smoothstep(0.45, 0.02, abs(swirl * 0.08 + radius - 0.52));
	vec3 color = mix(u_secondary, u_accent, swirl * 0.5 + 0.5);
	gl_FragColor = vec4(color, ring * (1.0 - smoothstep(0.2, 1.05, radius)) * u_intensity);
}
`,
}

const bundledPresetNames = ["aurora", "grid", "plasma", "nebula", "scanlines", "vortex", "custom"] as const

defineOptions({
	widget: declareWidgetOptions({
		id: "shaderLayer",
		name: "Shader Layer",
		description: "Renders a bundled or locally edited WebGL shader inside the overlay.",
		icon: "mdi mdi-magic-staff",
		defaultSize: { width: 900, height: 500 },
		config: {
			type: Object,
			properties: {
				preset: {
					type: String,
					name: "Shader Preset",
					default: "aurora",
					required: true,
					enum: ["aurora", "grid", "plasma", "nebula", "scanlines", "vortex", "custom"],
				},
				customFragmentShader: {
					type: String,
					name: "Custom Fragment Shader",
					default: "",
					multiLine: true,
				},
				accentColor: { type: String, name: "Accent Color", default: "#9146ff", required: true },
				secondaryColor: { type: String, name: "Secondary Color", default: "#00d1ff", required: true },
				intensity: { type: Number, name: "Intensity", default: 0.8, required: true },
				speed: { type: Number, name: "Speed", default: 1, required: true },
				opacity: { type: Number, name: "Opacity", default: 1, required: true },
				blendMode: {
					type: String,
					name: "Blend Mode",
					default: "normal",
					required: true,
					enum: ["normal", "screen", "overlay", "lighten", "multiply"],
				},
				text: { type: String, name: "Text", default: "", template: true },
			},
		},
	}),
})

const props = defineProps<{
	config: {
		preset: (typeof bundledPresetNames)[number]
		customFragmentShader?: string
		shaderGraph?: unknown
		shaderUniforms?: Record<string, number | number[]>
		accentColor: string
		secondaryColor: string
		intensity: number
		speed: number
		opacity: number
		blendMode: string
		text?: string
	}
}>()

const canvas = ref<HTMLCanvasElement>()
const errorMessage = ref("")
let renderer: ShaderRenderer | undefined

function getFragmentSource() {
	if (props.config.preset === "custom" && props.config.customFragmentShader?.trim()) {
		return props.config.customFragmentShader
	}
	return presets[props.config.preset] || presets.aurora
}

watch(
	() => [props.config.preset, props.config.customFragmentShader],
	() => {
		if (!renderer) return
		if (props.config.preset === "custom" && !props.config.customFragmentShader?.trim()) {
			errorMessage.value = "Custom shader is empty. Pick a bundled preset or paste a fragment shader source."
			return
		}
		const err = renderer.compileShader(getFragmentSource())
		errorMessage.value = err ?? ""
	},
)

onMounted(() => {
	if (!canvas.value) return
	try {
		renderer = new ShaderRenderer({
			canvas: canvas.value,
			fragmentSource: getFragmentSource(),
			getAccentColor: () => hexToVec3(props.config.accentColor, [0.57, 0.27, 1]),
			getSecondaryColor: () => hexToVec3(props.config.secondaryColor, [0, 0.82, 1]),
			getIntensity: () => Number(props.config.intensity ?? 0.8),
			getSpeed: () => Number(props.config.speed ?? 1),
			getCustomUniforms: () => props.config.shaderUniforms ?? {},
		})
	} catch (error) {
		errorMessage.value = error instanceof Error ? error.message : String(error)
	}
})

onUnmounted(() => {
	renderer?.dispose()
})

function hexToVec3(hex: string, fallback: [number, number, number]): [number, number, number] {
	const match = String(hex || "").match(/^#?([0-9a-f]{3}|[0-9a-f]{6})$/i)
	if (!match) return fallback
	let value = match[1]
	if (value.length === 3) value = value.split("").map((char) => char + char).join("")
	const parsed = Number.parseInt(value, 16)
	return [((parsed >> 16) & 255) / 255, ((parsed >> 8) & 255) / 255, (parsed & 255) / 255]
}
</script>

<style scoped>
.shader-layer {
	background: transparent;
	height: 100%;
	overflow: hidden;
	position: relative;
	width: 100%;
}

.shader-layer__canvas {
	display: block;
	height: 100%;
	width: 100%;
}

.shader-layer__fallback {
	align-items: center;
	background: rgba(10, 10, 14, 0.72);
	color: white;
	display: grid;
	gap: 0.25rem;
	inset: 0;
	justify-items: center;
	padding: 1rem;
	position: absolute;
	text-align: center;
}

.shader-layer__fallback span {
	color: rgba(255, 255, 255, 0.72);
	font-size: 0.8rem;
}

.shader-layer__text {
	color: white;
	font: 700 2rem/1.1 Inter, Arial, sans-serif;
	inset: auto 1rem 1rem;
	position: absolute;
	text-shadow: 0 0 18px rgba(0, 0, 0, 0.55);
}
</style>
