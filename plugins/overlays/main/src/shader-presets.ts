import { defineRendererCallable, ensureDirectory, ensureYAML, loadYAML, resolveProjectPath, writeYAML } from "showrunner-core"

type ShaderPresetStore = Record<string, string>

const DEFAULT_SHADER_PRESETS: ShaderPresetStore = {}

export function setupShaderPresets() {
	defineRendererCallable("listShaderPresets", async () => {
		return readShaderPresets()
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

	defineRendererCallable("deleteShaderPreset", async (name: string) => {
		const presets = await readShaderPresets()
		delete presets[String(name || "").trim()]
		await writeShaderPresets(presets)
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
