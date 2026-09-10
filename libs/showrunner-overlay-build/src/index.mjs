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
			if (widget.contracts !== undefined) validateContracts(widget.contracts, `${plugin.pluginId}.${widget.id}`)
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

function validateContracts(contracts, widgetKey) {
	if (!contracts || typeof contracts !== "object" || Array.isArray(contracts)) throw new Error(`Invalid contract metadata: ${widgetKey}`)
	for (const [event, schema] of Object.entries(contracts.events ?? {})) {
		if (!event || !schema || typeof schema !== "object" || Array.isArray(schema)) throw new Error(`Invalid event contract: ${widgetKey}.${event}`)
	}
	for (const [command, contract] of Object.entries(contracts.commands ?? {})) {
		if (!command || !contract || typeof contract !== "object" || Array.isArray(contract)) throw new Error(`Invalid command contract: ${widgetKey}.${command}`)
		if (contract.args !== undefined && (!contract.args || typeof contract.args !== "object" || Array.isArray(contract.args))) throw new Error(`Invalid command args contract: ${widgetKey}.${command}`)
		if (contract.result !== undefined && (!contract.result || typeof contract.result !== "object" || Array.isArray(contract.result))) throw new Error(`Invalid command result contract: ${widgetKey}.${command}`)
	}
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

function flutterCatalogFor(manifest) {
	const widgets = manifest.plugins.flatMap((plugin) => plugin.widgets.map((widget) => {
		const optional = [
			widget.description === undefined ? "" : `description: ${JSON.stringify(widget.description)},`,
			widget.icon === undefined ? "" : `icon: ${JSON.stringify(widget.icon)},`,
			widget.capabilities === undefined ? "" : `capabilities: ${JSON.stringify(widget.capabilities)},`,
		].filter(Boolean)
		return [
			"  GeneratedOverlayWidget(",
			`    pluginId: ${JSON.stringify(plugin.pluginId)},`,
			`    id: ${JSON.stringify(widget.id)},`,
			`    name: ${JSON.stringify(widget.name)},`,
			...optional.map((line) => `    ${line}`),
			`    defaultSize: ${JSON.stringify(widget.defaultSize)},`,
			`    config: ${JSON.stringify(widget.config ?? {})},`,
			"  ),",
		].join("\n")
	}))
	return [
		"// GENERATED FILE - DO NOT EDIT.",
		"",
		"import 'overlay_widget_catalog.dart';",
		"",
		"const generatedOverlayWidgets = <GeneratedOverlayWidget>[",
		...widgets,
		"];"]
}

function typeForSchema(schema, depth = 0) {
	if (!schema || typeof schema !== "object") return "unknown"
	const type = String(schema.type ?? "unknown").toLowerCase()
	if (Array.isArray(schema.enum) && schema.enum.length) {
		return schema.enum.map((value) => JSON.stringify(value)).join(" | ")
	}
	if (type === "tuple") {
		const items = Array.isArray(schema.items) ? schema.items : []
		return `readonly [${items.map((item) => `${typeForSchema(item, depth + 1)}${item?.optional === true ? "?" : ""}`).join(", ")}]`
	}
	if (type === "array" || type === "list") {
		const itemSchema = schema.itemSchema ?? schema.item
		return `readonly ${itemSchema ? typeForSchema(itemSchema, depth + 1) : "unknown"}[]`
	}
	if (type === "range") return "{ min?: number; max?: number }"
	if (type === "object" || type === "map" || type === "json") {
		const fields = schema.fields && typeof schema.fields === "object" && !Array.isArray(schema.fields) ? schema.fields : undefined
		if (!fields || Object.keys(fields).length === 0) return "Record<string, unknown>"
		const properties = Object.entries(fields).map(([key, value]) => propertyForSchema(key, value, depth + 1))
		return `{ ${properties.join("; ")} }`
	}
	if (type === "string" || type === "multiline" || type === "multilinetext" || type === "color" || type === "filepath" || type === "file" || type === "resource" || type === "viewervariable") return "string"
	if (type === "number" || type === "integer" || type === "float" || type === "duration") return "number"
	if (type === "boolean" || type === "bool") return "boolean"
	return "unknown"
}

function propertyForSchema(key, schema, depth = 0) {
	const metadata = schema && typeof schema === "object" ? schema : {}
	const optional = metadata.required === true ? "" : "?"
	return `${JSON.stringify(key)}${optional}: ${typeForSchema(metadata, depth)}`
}

function configTypeFor(config) {
	if (!config || typeof config !== "object" || Object.keys(config).length === 0) return "Record<string, unknown>"
	return `{ ${Object.entries(config).map(([key, schema]) => propertyForSchema(key, schema)).join("; ")} }`
}

function contractTypeFor(contract) {
	if (!contract || typeof contract !== "object") return "{ args: unknown; result: unknown }"
	return `{ args: ${typeForSchema(contract.args)}; result: ${typeForSchema(contract.result)} }`
}

function contractsFor(manifest) {
	const configEntries = []
	const events = new Map()
	const commands = new Map()
	for (const plugin of manifest.plugins) {
		for (const widget of plugin.widgets) {
			configEntries.push([`${plugin.pluginId}.${widget.id}`, configTypeFor(widget.config)])
			for (const event of widget.capabilities?.events ?? []) {
				if (!events.has(event)) events.set(event, "unknown")
			}
			for (const [event, contract] of Object.entries(widget.contracts?.events ?? {})) events.set(event, typeForSchema(contract))
			for (const command of widget.capabilities?.commands ?? []) {
				if (!commands.has(command)) commands.set(command, "{ args: unknown; result: unknown }")
			}
			for (const [command, contract] of Object.entries(widget.contracts?.commands ?? {})) commands.set(command, contractTypeFor(contract))
		}
	}
	const lines = [
		"// GENERATED FILE - DO NOT EDIT.",
		"",
		"/** Type-level contracts generated from plugin package manifests. */",
		"export interface GeneratedOverlayWidgetConfigMap {",
		...configEntries.sort(([a], [b]) => a.localeCompare(b)).map(([key, type]) => `\t${JSON.stringify(key)}: ${type}`),
		"}",
		"",
		"export type GeneratedOverlayWidgetKey = keyof GeneratedOverlayWidgetConfigMap",
		"export type GeneratedOverlayWidgetConfig<K extends GeneratedOverlayWidgetKey> = GeneratedOverlayWidgetConfigMap[K]",
		"",
		"export interface GeneratedOverlayEventMap {",
		...([...events.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([event, type]) => `\t${JSON.stringify(event)}: ${type}`)),
		"}",
		"",
		"export type GeneratedOverlayEventName = keyof GeneratedOverlayEventMap",
		"",
		"export interface GeneratedOverlayCommandMap {",
		...([...commands.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([command, type]) => `\t${JSON.stringify(command)}: ${type}`)),
		"}",
		"",
		"export type GeneratedOverlayCommandName = keyof GeneratedOverlayCommandMap",
		"",
	]
	return `${lines.join("\n")}\n`
}

export function generateRegistry({ pluginsRoot, outputDirectory, flutterManifestOutput, flutterCatalogLibraryOutput, coreContractsOutput }) {
	const plugins = discoverOverlayPlugins(pluginsRoot)
	const manifest = manifestFor(plugins)
	fs.mkdirSync(outputDirectory, { recursive: true })
	const imports = plugins.map((plugin, index) => {
		let importPath = path.relative(outputDirectory, plugin.entryPath).replaceAll(path.sep, "/")
		if (!importPath.startsWith(".")) importPath = `./${importPath}`
		return `import plugin${index} from ${JSON.stringify(importPath)}`
	})
	const source = [
		"// GENERATED FILE - DO NOT EDIT.",
		"",
		"import { bindOverlayPlugin, type OverlayPluginFactories, type OverlayPluginManifest } from \"showrunner-overlay-core\"",
		"import manifest from \"./overlay_widgets.generated.json\"",
		"",
		...imports,
		"",
		`const pluginFactories: readonly OverlayPluginFactories[] = [${plugins.map((_, index) => `plugin${index}`).join(", ")}]`,
		"",
		"export const builtInOverlayPlugins = (manifest.plugins as readonly OverlayPluginManifest[]).map((metadata) => {",
		"\tconst factories = pluginFactories.find((plugin) => plugin.pluginId === metadata.pluginId)",
		"\tif (!factories) throw new Error(`Missing overlay plugin factories: ${metadata.pluginId}`)",
		"\treturn bindOverlayPlugin(metadata, factories)",
		"})",
		"",
	].join("\n")
	fs.writeFileSync(path.join(outputDirectory, "overlay_plugins.generated.ts"), source)
	const manifestSource = `${JSON.stringify(manifest, null, 2)}\n`
	fs.writeFileSync(path.join(outputDirectory, "overlay_widgets.generated.json"), manifestSource)
	if (flutterManifestOutput) {
		fs.mkdirSync(path.dirname(flutterManifestOutput), { recursive: true })
		fs.writeFileSync(flutterManifestOutput, manifestSource)
	}
	if (flutterCatalogLibraryOutput) {
		fs.mkdirSync(path.dirname(flutterCatalogLibraryOutput), { recursive: true })
		fs.writeFileSync(flutterCatalogLibraryOutput, `${flutterCatalogFor(manifest).join("\n")}\n`)
	}
	if (coreContractsOutput) {
		fs.mkdirSync(path.dirname(coreContractsOutput), { recursive: true })
		fs.writeFileSync(coreContractsOutput, contractsFor(manifest))
	}
	return { plugins, manifest }
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
	const root = path.resolve(process.argv[2] ?? process.cwd())
	const outputDirectory = path.resolve(process.argv[3] ?? path.join(root, "packages/showrunner-obs-overlay/src/generated"))
	generateRegistry({ pluginsRoot: path.join(root, "plugins"), outputDirectory })
}
