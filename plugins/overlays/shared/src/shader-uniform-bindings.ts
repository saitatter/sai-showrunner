export type ShaderUniformValue = number | number[]

export type ShaderUniformBinding =
	| { source: "config"; path: string }
	| { source: "state"; plugin: string; state: string; path: string }

export type ShaderUniformBindingMap = Record<string, ShaderUniformBinding>

export interface ShaderUniformBindingContext {
	config?: Record<string, unknown>
	states?: Record<string, Record<string, unknown>>
}

export function resolveShaderUniformBindings(
	defaults: Record<string, ShaderUniformValue> = {},
	bindings: ShaderUniformBindingMap = {},
	context: ShaderUniformBindingContext = {}
) {
	const resolved: Record<string, ShaderUniformValue> = { ...defaults }

	for (const [uniformName, binding] of Object.entries(bindings)) {
		const fallback = resolved[uniformName]
		const sourceValue = resolveBindingValue(binding, context)
		const value = coerceUniformValue(sourceValue, fallback)
		if (value != null) resolved[uniformName] = value
	}

	return resolved
}

function resolveBindingValue(binding: ShaderUniformBinding, context: ShaderUniformBindingContext) {
	if (binding.source === "config") return getPath(context.config, binding.path)
	const pluginState = context.states?.[binding.plugin]?.[binding.state]
	return getPath(pluginState, binding.path)
}

function getPath(source: unknown, path: string) {
	if (!source || typeof source !== "object") return undefined
	const segments = path.split(".").map((part) => part.trim()).filter(Boolean)
	let current: unknown = source
	for (const segment of segments) {
		if (!current || typeof current !== "object") return undefined
		current = (current as Record<string, unknown>)[segment]
	}
	return current
}

function coerceUniformValue(value: unknown, fallback: ShaderUniformValue | undefined): ShaderUniformValue | undefined {
	if (Array.isArray(fallback)) {
		const values = coerceNumberArray(value)
		if (!values.length) return undefined
		return fallback.map((_, index) => values[index] ?? fallback[index])
	}

	if (typeof fallback === "number" || fallback == null) {
		const number = coerceNumber(value)
		return number == null ? undefined : number
	}

	return undefined
}

function coerceNumberArray(value: unknown) {
	if (Array.isArray(value)) {
		return value.map(coerceNumber).filter((item): item is number => item != null)
	}
	if (typeof value === "string") {
		return value.match(/[-+]?\d*\.?\d+/g)?.map(Number).filter(Number.isFinite) ?? []
	}
	const number = coerceNumber(value)
	return number == null ? [] : [number]
}

function coerceNumber(value: unknown) {
	if (typeof value === "number") return Number.isFinite(value) ? value : undefined
	if (typeof value === "boolean") return value ? 1 : 0
	if (typeof value === "string") {
		const parsed = Number(value.trim())
		return Number.isFinite(parsed) ? parsed : undefined
	}
	return undefined
}
