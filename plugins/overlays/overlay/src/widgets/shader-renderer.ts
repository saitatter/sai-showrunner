/**
 * WebGL shader renderer — handles compilation, uniform binding, and frame loop.
 * Extracted from ShaderLayer.vue for maintainability.
 */

export interface ShaderRendererOptions {
	canvas: HTMLCanvasElement
	fragmentSource: string
	getAccentColor: () => [number, number, number]
	getSecondaryColor: () => [number, number, number]
	getIntensity: () => number
	getSpeed: () => number
	getCustomUniforms?: () => Record<string, number | number[]>
}

const vertexShaderSource = `
attribute vec2 a_position;
void main() {
	gl_Position = vec4(a_position, 0.0, 1.0);
}
`

export class ShaderRenderer {
	private gl: WebGLRenderingContext
	private program: WebGLProgram | undefined
	private positionBuffer: WebGLBuffer
	private animationFrame = 0
	private resizeObserver: ResizeObserver
	private startedAt = performance.now()
	private options: ShaderRendererOptions

	constructor(options: ShaderRendererOptions) {
		this.options = options
		const gl = options.canvas.getContext("webgl", { alpha: true })
		if (!gl) throw new Error("WebGL is not available.")
		this.gl = gl

		const buffer = gl.createBuffer()
		if (!buffer) throw new Error("Failed to create WebGL buffer.")
		this.positionBuffer = buffer

		gl.bindBuffer(gl.ARRAY_BUFFER, this.positionBuffer)
		gl.bufferData(
			gl.ARRAY_BUFFER,
			new Float32Array([-1, -1, 1, -1, -1, 1, -1, 1, 1, -1, 1, 1]),
			gl.STATIC_DRAW
		)

		this.resizeObserver = new ResizeObserver(() => this.resize())
		this.resizeObserver.observe(options.canvas)

		this.compileShader(options.fragmentSource)
		this.render()
	}

	compileShader(fragmentSource: string): string | null {
		const gl = this.gl
		try {
			const nextProgram = this.createProgram(fragmentSource)
			if (this.program) gl.deleteProgram(this.program)
			this.program = nextProgram
			this.startedAt = performance.now()
			return null
		} catch (error) {
			return error instanceof Error ? error.message : String(error)
		}
	}

	dispose() {
		cancelAnimationFrame(this.animationFrame)
		this.resizeObserver.disconnect()
		if (this.positionBuffer) this.gl.deleteBuffer(this.positionBuffer)
		if (this.program) this.gl.deleteProgram(this.program)
	}

	private render = () => {
		const { gl, program, options } = this
		const canvas = options.canvas
		if (!program) return

		this.resize()
		const positionLocation = gl.getAttribLocation(program, "a_position")
		gl.clearColor(0, 0, 0, 0)
		gl.clear(gl.COLOR_BUFFER_BIT)
		gl.useProgram(program)
		gl.bindBuffer(gl.ARRAY_BUFFER, this.positionBuffer)
		gl.enableVertexAttribArray(positionLocation)
		gl.vertexAttribPointer(positionLocation, 2, gl.FLOAT, false, 0, 0)

		const uResolution = gl.getUniformLocation(program, "u_resolution")
		const uTime = gl.getUniformLocation(program, "u_time")
		const uAccent = gl.getUniformLocation(program, "u_accent")
		const uSecondary = gl.getUniformLocation(program, "u_secondary")
		const uIntensity = gl.getUniformLocation(program, "u_intensity")
		const uSpeed = gl.getUniformLocation(program, "u_speed")

		if (uResolution) gl.uniform2f(uResolution, canvas.width, canvas.height)
		if (uTime) gl.uniform1f(uTime, (performance.now() - this.startedAt) / 1000)
		if (uAccent) gl.uniform3fv(uAccent, options.getAccentColor())
		if (uSecondary) gl.uniform3fv(uSecondary, options.getSecondaryColor())
		if (uIntensity) gl.uniform1f(uIntensity, options.getIntensity())
		if (uSpeed) gl.uniform1f(uSpeed, options.getSpeed())
		this.applyCustomUniforms()

		gl.drawArrays(gl.TRIANGLES, 0, 6)
		this.animationFrame = requestAnimationFrame(this.render)
	}

	private applyCustomUniforms() {
		const { gl, program, options } = this
		if (!program) return
		const uniforms = options.getCustomUniforms?.() ?? {}
		for (const [name, value] of Object.entries(uniforms)) {
			const location = gl.getUniformLocation(program, name)
			if (!location) continue
			if (typeof value === "number") gl.uniform1f(location, value)
			else if (value.length === 2) gl.uniform2fv(location, value)
			else if (value.length === 3) gl.uniform3fv(location, value)
			else if (value.length === 4) gl.uniform4fv(location, value)
		}
	}

	private resize() {
		const { gl, options } = this
		const canvas = options.canvas
		const pixelRatio = Math.max(1, Math.min(window.devicePixelRatio || 1, 2))
		const width = Math.max(1, Math.floor(canvas.clientWidth * pixelRatio))
		const height = Math.max(1, Math.floor(canvas.clientHeight * pixelRatio))
		if (canvas.width === width && canvas.height === height) return
		canvas.width = width
		canvas.height = height
		gl.viewport(0, 0, width, height)
	}

	private createShader(type: number, source: string): WebGLShader {
		const gl = this.gl
		const shader = gl.createShader(type)
		if (!shader) throw new Error("Failed to create shader.")
		gl.shaderSource(shader, source)
		gl.compileShader(shader)
		if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
			const message = gl.getShaderInfoLog(shader) || "Shader compilation failed."
			gl.deleteShader(shader)
			throw new Error(message)
		}
		return shader
	}

	private createProgram(fragmentSource: string): WebGLProgram {
		const gl = this.gl
		const nextProgram = gl.createProgram()
		if (!nextProgram) throw new Error("Failed to create shader program.")
		const vertexShader = this.createShader(gl.VERTEX_SHADER, vertexShaderSource)
		const fragmentShader = this.createShader(gl.FRAGMENT_SHADER, fragmentSource)
		try {
			gl.attachShader(nextProgram, vertexShader)
			gl.attachShader(nextProgram, fragmentShader)
			gl.linkProgram(nextProgram)
			if (!gl.getProgramParameter(nextProgram, gl.LINK_STATUS)) {
				throw new Error(gl.getProgramInfoLog(nextProgram) || "Shader linking failed.")
			}
			return nextProgram
		} catch (error) {
			gl.deleteProgram(nextProgram)
			throw error
		} finally {
			gl.deleteShader(vertexShader)
			gl.deleteShader(fragmentShader)
		}
	}
}
