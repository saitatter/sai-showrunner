import fs from "node:fs"
import path from "node:path"
import { pathToFileURL } from "node:url"

const overlayManifestKey = "showrunner"

function packageFiles(root) {
	const result = []
	const visit = (directory) => {
		for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
			if (entry.name === "node_modules" || entry.name === ".git" || entry.name === "dist") continue
			const fullPath = path.join(directory, entry.name)
			if (entry.isDirectory()) visit(fullPath)
			else if (entry.name === "package.json") result.push(fullPath)
		}
	}
	visit(root)
	return result
}

export function discoverOverlayPlugins(pluginsRoot) {
	const discovered = []
	for (const packagePath of packageFiles(pluginsRoot)) {
		const packageJson = JSON.parse(fs.readFileSync(packagePath, "utf8"))
		const overlay = packageJson[overlayManifestKey]?.overlay
		const pluginId = packageJson[overlayManifestKey]?.pluginId
		if (!overlay) continue
		if (!pluginId) throw new Error(`${packagePath}: showrunner.pluginId is required`)
		if (!overlay.entry || typeof overlay.entry !== "string") throw new Error(`${packagePath}: showrunner.overlay.entry is required`)
		const entryPath = path.resolve(path.dirname(packagePath), overlay.entry)
		if (!fs.existsSync(entryPath)) throw new Error(`${packagePath}: overlay entry does not exist: ${overlay.entry}`)
		const widgets = overlay.widgets ?? []
		if (!Array.isArray(widgets)) throw new Error(`${packagePath}: showrunner.overlay.widgets must be an array`)
		discovered.push({ pluginId, packageName: packageJson.name, packagePath, entryPath, widgets })
	}
	return validateOverlayPlugins(discovered).sort((a, b) => a.pluginId.localeCompare(b.pluginId))
}

export function validateOverlayPlugins(plugins) {
	const pluginIds = new Set()
	const widgetKeys = new Set()
	for (const plugin of plugins) {
		if (!/^[a-z0-9][a-z0-9-]*$/.test(plugin.pluginId)) throw new Error(`Invalid overlay plugin ID: ${plugin.pluginId}`)
		if (pluginIds.has(plugin.pluginId)) throw new Error(`Duplicate overlay plugin ID: ${plugin.pluginId}`)
		pluginIds.add(plugin.pluginId)
		const widgetIds = new Set()
		for (const widget of plugin.widgets) {
			if (!widget.id || typeof widget.id !== "string") throw new Error(`${plugin.pluginId}: widget id is required`)
			if (!/^[a-z][a-zA-Z0-9-]*$/.test(widget.id)) throw new Error(`Invalid widget ID: ${plugin.pluginId}.${widget.id}`)
			if (widgetIds.has(widget.id)) throw new Error(`Duplicate widget ID: ${plugin.pluginId}.${widget.id}`)
			if (!widget.name || typeof widget.name !== "string") throw new Error(`${plugin.pluginId}.${widget.id}: widget name is required`)
			if (widget.config !== undefined && (typeof widget.config !== "object" || Array.isArray(widget.config))) {
				throw new Error(`Invalid config metadata: ${plugin.pluginId}.${widget.id}`)
			}
			widgetIds.add(widget.id)
			const key = `${plugin.pluginId}.${widget.id}`
			if (widgetKeys.has(key)) throw new Error(`Duplicate overlay widget key: ${key}`)
			widgetKeys.add(key)
			if (!widget.defaultSize || !validDimension(widget.defaultSize.width) || !validDimension(widget.defaultSize.height)) {
				throw new Error(`Invalid default dimensions: ${key}`)
			}
		}
	}
	return plugins.map((plugin) => ({ ...plugin, widgets: [...plugin.widgets].sort((a, b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0) }))
}

function validDimension(value) {
	return value === "canvas" || (typeof value === "number" && Number.isFinite(value) && value > 0)
}

function manifestFor(plugins) {
	return {
		schemaVersion: 1,
		plugins: plugins.map((plugin) => ({
			pluginId: plugin.pluginId,
			widgets: [...plugin.widgets].sort((a, b) => a.id.localeCompare(b.id)),
		})),
	}
}

export function generateRegistry({ pluginsRoot, outputDirectory, flutterManifestOutput }) {
	const plugins = discoverOverlayPlugins(pluginsRoot)
	fs.mkdirSync(outputDirectory, { recursive: true })
	const imports = plugins.map((plugin, index) => {
		let importPath = path.relative(outputDirectory, plugin.entryPath).replaceAll(path.sep, "/")
		if (!importPath.startsWith(".")) importPath = `./${importPath}`
		return `import plugin${index} from ${JSON.stringify(importPath)}`
	})
	const source = [
		"// GENERATED FILE - DO NOT EDIT.",
		"",
		...imports,
		"",
		`export const builtInOverlayPlugins = [${plugins.map((_, index) => `plugin${index}`).join(", ")}] as const`,
		"",
	].join("\n")
	fs.writeFileSync(path.join(outputDirectory, "overlay_plugins.generated.ts"), source)
	const manifestSource = `${JSON.stringify(manifestFor(plugins), null, 2)}\n`
	fs.writeFileSync(path.join(outputDirectory, "overlay_widgets.generated.json"), manifestSource)
	if (flutterManifestOutput) {
		fs.mkdirSync(path.dirname(flutterManifestOutput), { recursive: true })
		fs.writeFileSync(flutterManifestOutput, manifestSource)
	}
	return { plugins, manifest: manifestFor(plugins) }
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
	const root = path.resolve(process.argv[2] ?? process.cwd())
	const outputDirectory = path.resolve(process.argv[3] ?? path.join(root, "packages/showrunner-obs-overlay/src/generated"))
	generateRegistry({ pluginsRoot: path.join(root, "plugins"), outputDirectory })
}
