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
import { declareWidgetOptions } from "castmate-overlay-core"

const vertexShaderSource = `
attribute vec2 a_position;
void main() {
	gl_Position = vec4(a_position, 0.0, 1.0);
}
`

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
}

defineOptions({
	widget: declareWidgetOptions({
		id: "shaderLayer",
		name: "Shader Layer",
		description: "Renders a bundled WebGL shader preset inside the overlay.",
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
					enum: ["aurora", "grid", "plasma"],
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
		preset: "aurora" | "grid" | "plasma"
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
let gl: WebGLRenderingContext | undefined
let program: WebGLProgram | undefined
let positionBuffer: WebGLBuffer | undefined
let animationFrame = 0
let resizeObserver: ResizeObserver | undefined
let startedAt = performance.now()

watch(
	() => props.config.preset,
	() => {
		if (!gl) return
		compilePreset()
	},
)

onMounted(() => {
	try {
		gl = canvas.value?.getContext("webgl", { alpha: true }) ?? undefined
		if (!gl) throw new Error("WebGL is not available.")
		positionBuffer = gl.createBuffer() ?? undefined
		if (!positionBuffer) throw new Error("Failed to create WebGL buffer.")
		gl.bindBuffer(gl.ARRAY_BUFFER, positionBuffer)
		gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, -1, 1, 1, -1, 1, 1]), gl.STATIC_DRAW)
		compilePreset()
		resizeObserver = new ResizeObserver(resize)
		if (canvas.value) resizeObserver.observe(canvas.value)
		render()
	} catch (error) {
		errorMessage.value = error instanceof Error ? error.message : String(error)
	}
})

onUnmounted(() => {
	cancelAnimationFrame(animationFrame)
	resizeObserver?.disconnect()
	if (gl && positionBuffer) gl.deleteBuffer(positionBuffer)
	if (gl && program) gl.deleteProgram(program)
})

function compilePreset() {
	if (!gl) return
	const nextProgram = createProgram(gl, presets[props.config.preset] || presets.aurora)
	if (program) gl.deleteProgram(program)
	program = nextProgram
	startedAt = performance.now()
	errorMessage.value = ""
}

function render() {
	if (!gl || !program || !canvas.value) return
	resize()
	const positionLocation = gl.getAttribLocation(program, "a_position")
	gl.clearColor(0, 0, 0, 0)
	gl.clear(gl.COLOR_BUFFER_BIT)
	gl.useProgram(program)
	gl.bindBuffer(gl.ARRAY_BUFFER, positionBuffer ?? null)
	gl.enableVertexAttribArray(positionLocation)
	gl.vertexAttribPointer(positionLocation, 2, gl.FLOAT, false, 0, 0)
	gl.uniform2f(gl.getUniformLocation(program, "u_resolution"), canvas.value.width, canvas.value.height)
	gl.uniform1f(gl.getUniformLocation(program, "u_time"), (performance.now() - startedAt) / 1000)
	gl.uniform3fv(gl.getUniformLocation(program, "u_accent"), hexToVec3(props.config.accentColor, [0.57, 0.27, 1]))
	gl.uniform3fv(gl.getUniformLocation(program, "u_secondary"), hexToVec3(props.config.secondaryColor, [0, 0.82, 1]))
	gl.uniform1f(gl.getUniformLocation(program, "u_intensity"), Number(props.config.intensity ?? 0.8))
	gl.uniform1f(gl.getUniformLocation(program, "u_speed"), Number(props.config.speed ?? 1))
	gl.drawArrays(gl.TRIANGLES, 0, 6)
	animationFrame = requestAnimationFrame(render)
}

function resize() {
	if (!gl || !canvas.value) return
	const pixelRatio = Math.max(1, Math.min(window.devicePixelRatio || 1, 2))
	const width = Math.max(1, Math.floor(canvas.value.clientWidth * pixelRatio))
	const height = Math.max(1, Math.floor(canvas.value.clientHeight * pixelRatio))
	if (canvas.value.width === width && canvas.value.height === height) return
	canvas.value.width = width
	canvas.value.height = height
	gl.viewport(0, 0, width, height)
}

function createShader(context: WebGLRenderingContext, type: number, source: string) {
	const shader = context.createShader(type)
	if (!shader) throw new Error("Failed to create shader.")
	context.shaderSource(shader, source)
	context.compileShader(shader)
	if (!context.getShaderParameter(shader, context.COMPILE_STATUS)) {
		const message = context.getShaderInfoLog(shader) || "Shader compilation failed."
		context.deleteShader(shader)
		throw new Error(message)
	}
	return shader
}

function createProgram(context: WebGLRenderingContext, fragmentSource: string) {
	const nextProgram = context.createProgram()
	if (!nextProgram) throw new Error("Failed to create shader program.")
	const vertexShader = createShader(context, context.VERTEX_SHADER, vertexShaderSource)
	const fragmentShader = createShader(context, context.FRAGMENT_SHADER, fragmentSource)
	try {
		context.attachShader(nextProgram, vertexShader)
		context.attachShader(nextProgram, fragmentShader)
		context.linkProgram(nextProgram)
		if (!context.getProgramParameter(nextProgram, context.LINK_STATUS)) {
			throw new Error(context.getProgramInfoLog(nextProgram) || "Shader linking failed.")
		}
		return nextProgram
	} catch (error) {
		context.deleteProgram(nextProgram)
		throw error
	} finally {
		context.deleteShader(vertexShader)
		context.deleteShader(fragmentShader)
	}
}

function hexToVec3(hex: string, fallback: [number, number, number]) {
	const match = String(hex || "").match(/^#?([0-9a-f]{3}|[0-9a-f]{6})$/i)
	if (!match) return fallback
	let value = match[1]
	if (value.length === 3) value = value.split("").map((char) => char + char).join("")
	const parsed = Number.parseInt(value, 16)
	return [((parsed >> 16) & 255) / 255, ((parsed >> 8) & 255) / 255, (parsed & 255) / 255] as [
		number,
		number,
		number,
	]
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
