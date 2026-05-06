import { defineRendererCallable, ensureDirectory, ensureYAML, loadYAML, resolveProjectPath, writeYAML } from "showrunner-core"

type ShaderPresetStore = Record<string, string>
type ShaderGraphPresetStore = Record<string, unknown>

const DEFAULT_SHADER_PRESETS: ShaderPresetStore = {}
const DEFAULT_SHADER_GRAPH_PRESETS: ShaderGraphPresetStore = {}

export function setupShaderPresets() {
	defineRendererCallable("listShaderPresets", async () => {
		return readShaderPresets()
	})

	defineRendererCallable("listShaderGraphPresets", async () => {
		return readShaderGraphPresets()
	})

	defineRendererCallable("saveShaderPreset", async (preset: { name?: string; source?: string }) => {
		const name = String(preset.name || "").trim()
		const source = String(preset.source || "").trim()
		if (!name) throw new Error("Shader preset name is required.")
		if (!source) throw new Error("Shader preset source is required.")

		const presets = await readShaderPresets()
		presets[name] = source
		await writeShaderPresets(presets)
		return presets
	})

	defineRendererCallable("saveShaderGraphPreset", async (preset: { name?: string; graph?: unknown }) => {
		const name = String(preset.name || "").trim()
		if (!name) throw new Error("Shader graph preset name is required.")
		if (!preset.graph || typeof preset.graph !== "object") throw new Error("Shader graph preset graph is required.")

		const presets = await readShaderGraphPresets()
		presets[name] = preset.graph
		await writeShaderGraphPresets(presets)
		return presets
	})

	defineRendererCallable("deleteShaderPreset", async (name: string) => {
		const presets = await readShaderPresets()
		delete presets[String(name || "").trim()]
		await writeShaderPresets(presets)
		return presets
	})

	defineRendererCallable("deleteShaderGraphPreset", async (name: string) => {
		const presets = await readShaderGraphPresets()
		delete presets[String(name || "").trim()]
		await writeShaderGraphPresets(presets)
		return presets
	})
}

async function readShaderPresets(): Promise<ShaderPresetStore> {
	await ensureDirectory(resolveProjectPath("overlays"))
	await ensureYAML(DEFAULT_SHADER_PRESETS, "overlays", "shader-presets.yaml")
	return await loadYAML<ShaderPresetStore>("overlays", "shader-presets.yaml")
}

async function writeShaderPresets(presets: ShaderPresetStore) {
	await ensureDirectory(resolveProjectPath("overlays"))
	await writeYAML(presets, "overlays", "shader-presets.yaml")
}

async function readShaderGraphPresets(): Promise<ShaderGraphPresetStore> {
	await ensureDirectory(resolveProjectPath("overlays"))
	await ensureYAML(DEFAULT_SHADER_GRAPH_PRESETS, "overlays", "shader-graph-presets.yaml")
	return await loadYAML<ShaderGraphPresetStore>("overlays", "shader-graph-presets.yaml")
}

async function writeShaderGraphPresets(presets: ShaderGraphPresetStore) {
	await ensureDirectory(resolveProjectPath("overlays"))
	await writeYAML(presets, "overlays", "shader-graph-presets.yaml")
}
