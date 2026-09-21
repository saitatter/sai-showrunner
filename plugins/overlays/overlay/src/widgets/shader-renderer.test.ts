import { afterEach, describe, expect, it, vi } from "vitest"
import { ShaderRenderer } from "./shader-renderer"

type FakeShader = { type: number; source: string; compiled: boolean }
type FakeProgram = { shaders: FakeShader[]; linked: boolean }

class FakeWebGLRenderingContext {
	readonly ARRAY_BUFFER = 0x8892
	readonly STATIC_DRAW = 0x88e4
	readonly VERTEX_SHADER = 0x8b31
	readonly FRAGMENT_SHADER = 0x8b30
	readonly COMPILE_STATUS = 0x8b81
	readonly LINK_STATUS = 0x8b82
	readonly COLOR_BUFFER_BIT = 0x4000
	readonly FLOAT = 0x1406
	readonly TRIANGLES = 0x0004
	readonly calls: string[] = []

	createBuffer(): WebGLBuffer {
		return {} as WebGLBuffer
	}

	bindBuffer(): void {
		this.calls.push("bindBuffer")
	}

	bufferData(): void {
		this.calls.push("bufferData")
	}

	deleteBuffer(): void {
		this.calls.push("deleteBuffer")
	}

	createShader(type: number): WebGLShader {
		return { type, source: "", compiled: true } as unknown as WebGLShader
	}

	shaderSource(shader: WebGLShader, source: string): void {
		;(shader as unknown as FakeShader).source = source
	}

	compileShader(shader: WebGLShader): void {
		const fakeShader = shader as unknown as FakeShader
		fakeShader.compiled = !fakeShader.source.includes("invalid_shader")
	}

	getShaderParameter(shader: WebGLShader, parameter: number): boolean {
		return parameter === this.COMPILE_STATUS && (shader as unknown as FakeShader).compiled
	}

	getShaderInfoLog(): string {
		return "fake shader compilation error"
	}

	deleteShader(): void {
		this.calls.push("deleteShader")
	}

	createProgram(): WebGLProgram {
		return { shaders: [], linked: true } as unknown as WebGLProgram
	}

	attachShader(program: WebGLProgram, shader: WebGLShader): void {
		;(program as unknown as FakeProgram).shaders.push(shader as unknown as FakeShader)
	}

	linkProgram(program: WebGLProgram): void {
		;(program as unknown as FakeProgram).linked = (program as unknown as FakeProgram).shaders.every(
			(shader) => shader.compiled,
		)
	}

	getProgramParameter(program: WebGLProgram, parameter: number): boolean {
		return parameter === this.LINK_STATUS && (program as unknown as FakeProgram).linked
	}

	getProgramInfoLog(): string {
		return "fake program link error"
	}

	deleteProgram(): void {
		this.calls.push("deleteProgram")
	}

	getAttribLocation(): number {
		return 0
	}

	clearColor(): void {
		this.calls.push("clearColor")
	}

	clear(): void {
		this.calls.push("clear")
	}

	useProgram(): void {
		this.calls.push("useProgram")
	}

	enableVertexAttribArray(): void {
		this.calls.push("enableVertexAttribArray")
	}

	vertexAttribPointer(): void {
		this.calls.push("vertexAttribPointer")
	}

	getUniformLocation(_program: WebGLProgram, name: string): WebGLUniformLocation | null {
		return { name } as unknown as WebGLUniformLocation
	}

	uniform2f(): void {
		this.calls.push("uniform2f")
	}

	uniform1f(): void {
		this.calls.push("uniform1f")
	}

	uniform3fv(): void {
		this.calls.push("uniform3fv")
	}

	uniform2fv(): void {
		this.calls.push("uniform2fv")
	}

	uniform4fv(): void {
		this.calls.push("uniform4fv")
	}

	drawArrays(): void {
		this.calls.push("drawArrays")
	}

	viewport(): void {
		this.calls.push("viewport")
	}
}

class FakeResizeObserver {
	constructor(_callback: ResizeObserverCallback) {}
	observe(): void {}
	disconnect(): void {}
}

function createCanvas(gl: FakeWebGLRenderingContext): HTMLCanvasElement {
	return {
		clientWidth: 320,
		clientHeight: 180,
		width: 0,
		height: 0,
		getContext: () => gl,
	} as unknown as HTMLCanvasElement
}

function createOptions(canvas: HTMLCanvasElement, fragmentSource = "void main() {}"): {
	canvas: HTMLCanvasElement
	fragmentSource: string
	getAccentColor: () => [number, number, number]
	getSecondaryColor: () => [number, number, number]
	getIntensity: () => number
	getSpeed: () => number
	getCustomUniforms: () => Record<string, number | number[]>
} {
	return {
		canvas,
		fragmentSource,
		getAccentColor: () => [1, 0, 0],
		getSecondaryColor: () => [0, 1, 0],
		getIntensity: () => 0.75,
		getSpeed: () => 1.5,
		getCustomUniforms: () => ({ u_detail: 0.25, u_offset: [0.1, 0.2] }),
	}
}

describe("ShaderRenderer", () => {
	afterEach(() => vi.unstubAllGlobals())

	it("renders a valid shader and applies built-in and custom uniforms", () => {
		const gl = new FakeWebGLRenderingContext()
		vi.stubGlobal("ResizeObserver", FakeResizeObserver)
		vi.stubGlobal("requestAnimationFrame", () => 1)
		vi.stubGlobal("cancelAnimationFrame", vi.fn())
		vi.stubGlobal("window", { devicePixelRatio: 1 })

		const renderer = new ShaderRenderer(createOptions(createCanvas(gl)))

		expect(gl.calls).toContain("drawArrays")
		expect(gl.calls.filter((call) => call === "uniform1f")).toHaveLength(4)
		expect(gl.calls).toContain("uniform3fv")
		expect(gl.calls).toContain("uniform2fv")
		renderer.dispose()
	})

	it("returns a compile error while preserving the current program", () => {
		const gl = new FakeWebGLRenderingContext()
		vi.stubGlobal("ResizeObserver", FakeResizeObserver)
		vi.stubGlobal("requestAnimationFrame", () => 1)
		vi.stubGlobal("cancelAnimationFrame", vi.fn())
		vi.stubGlobal("window", { devicePixelRatio: 1 })

		const renderer = new ShaderRenderer(createOptions(createCanvas(gl)))
		const error = renderer.compileShader("invalid_shader")

		expect(error).toBe("fake shader compilation error")
		expect(gl.calls.filter((call) => call === "drawArrays")).toHaveLength(1)
		renderer.dispose()
	})

	it("throws on an invalid initial shader so the widget can render its fallback", () => {
		const gl = new FakeWebGLRenderingContext()
		vi.stubGlobal("ResizeObserver", FakeResizeObserver)
		vi.stubGlobal("requestAnimationFrame", () => 1)
		vi.stubGlobal("cancelAnimationFrame", vi.fn())
		vi.stubGlobal("window", { devicePixelRatio: 1 })

		expect(() => new ShaderRenderer(createOptions(createCanvas(gl), "invalid_shader"))).toThrow(
			"fake shader compilation error",
		)
		expect(gl.calls).toContain("deleteBuffer")
	})
})
