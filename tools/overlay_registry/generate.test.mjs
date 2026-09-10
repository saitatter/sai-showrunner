import fs from "node:fs"
import os from "node:os"
import path from "node:path"
import { afterEach, describe, expect, it } from "vitest"
import { discoverOverlayPlugins, generateRegistry } from "../../libs/showrunner-overlay-build/src/index.mjs"

const temporaryDirectories = []
function fixture() {
	const root = fs.mkdtempSync(path.join(os.tmpdir(), "showrunner-overlay-registry-"))
	temporaryDirectories.push(root)
	return root
}

afterEach(() => { for (const directory of temporaryDirectories.splice(0)) fs.rmSync(directory, { recursive: true, force: true }) })

describe("overlay registry generation", () => {
	it("discovers overlay entries, ignores non-overlay packages, and sorts output", () => {
		const root = fixture(); const plugins = path.join(root, "plugins"); fs.mkdirSync(plugins, { recursive: true })
		for (const [directory, id] of [["zeta", "zeta"], ["alpha", "alpha"]]) {
			const packageDirectory = path.join(plugins, directory); fs.mkdirSync(path.join(packageDirectory, "src"), { recursive: true })
			fs.writeFileSync(path.join(packageDirectory, "src", "main.ts"), "export default {}")
			fs.writeFileSync(path.join(packageDirectory, "package.json"), JSON.stringify({ name: directory, showrunner: { pluginId: id, overlay: { entry: "./src/main.ts", widgets: [{ id: "widget", name: "Widget", defaultSize: { width: 10, height: 10 } }] } } }))
		}
		const ignored = path.join(plugins, "ignored"); fs.mkdirSync(ignored); fs.writeFileSync(path.join(ignored, "package.json"), JSON.stringify({ name: "ignored" }))
		const output = path.join(root, "generated"); const flutterCatalog = path.join(root, "flutter", "overlay_widget_catalog.generated.dart"); const coreContracts = path.join(root, "core", "overlay-contracts.generated.ts")
		const result = generateRegistry({ pluginsRoot: plugins, outputDirectory: output, flutterCatalogLibraryOutput: flutterCatalog, coreContractsOutput: coreContracts })
		expect(result.plugins.map((plugin) => plugin.pluginId)).toEqual(["alpha", "zeta"])
		expect(fs.readFileSync(path.join(output, "overlay_plugins.generated.ts"), "utf8")).toContain("plugin0")
		expect(JSON.parse(fs.readFileSync(path.join(output, "overlay_widgets.generated.json"), "utf8")).schemaVersion).toBe(1)
		expect(fs.readFileSync(flutterCatalog, "utf8")).toContain("GeneratedOverlayWidget")
		expect(fs.readFileSync(flutterCatalog, "utf8")).toContain('pluginId: "alpha"')
		expect(fs.readFileSync(coreContracts, "utf8")).toContain('"alpha.widget"')
		expect(fs.readFileSync(coreContracts, "utf8")).toContain("GeneratedOverlayCommandMap")
	})

	it("fails duplicate IDs and invalid dimensions", () => {
		const root = fixture(); const plugins = path.join(root, "plugins"); fs.mkdirSync(plugins, { recursive: true })
		const write = (name, id, dimensions = { width: 10, height: 10 }) => {
			const directory = path.join(plugins, name); fs.mkdirSync(path.join(directory, "src"), { recursive: true }); fs.writeFileSync(path.join(directory, "src", "main.ts"), "export default {}")
			fs.writeFileSync(path.join(directory, "package.json"), JSON.stringify({ name, showrunner: { pluginId: id, overlay: { entry: "./src/main.ts", widgets: [{ id: "widget", name: "Widget", defaultSize: dimensions }] } } }))
		}
		write("one", "same"); write("two", "same")
		expect(() => discoverOverlayPlugins(plugins)).toThrow("Duplicate overlay plugin ID")
		fs.rmSync(path.join(plugins, "two"), { recursive: true, force: true }); write("two", "two", { width: 0, height: 10 })
		expect(() => discoverOverlayPlugins(plugins)).toThrow("Invalid default dimensions")
	})

	it("fails a missing overlay entry", () => {
		const root = fixture(); const plugins = path.join(root, "plugins"); const directory = path.join(plugins, "broken")
		fs.mkdirSync(directory, { recursive: true })
		fs.writeFileSync(path.join(directory, "package.json"), JSON.stringify({ name: "broken", showrunner: { pluginId: "broken", overlay: { entry: "./missing.ts", widgets: [] } } }))
		expect(() => discoverOverlayPlugins(plugins)).toThrow("overlay entry does not exist")
	})

	it("produces byte-stable output for the same manifests", () => {
		const root = fixture(); const plugins = path.join(root, "plugins"); const directory = path.join(plugins, "stable")
		fs.mkdirSync(path.join(directory, "src"), { recursive: true })
		fs.writeFileSync(path.join(directory, "src", "main.ts"), "export default {}")
		fs.writeFileSync(path.join(directory, "package.json"), JSON.stringify({ name: "stable", showrunner: { pluginId: "stable", overlay: { entry: "./src/main.ts", widgets: [{ id: "widget", name: "Widget", defaultSize: { width: 10, height: 10 } }] } } }))
		const first = path.join(root, "one"); const second = path.join(root, "two")
		generateRegistry({ pluginsRoot: plugins, outputDirectory: first })
		generateRegistry({ pluginsRoot: plugins, outputDirectory: second })
		expect(fs.readFileSync(path.join(first, "overlay_plugins.generated.ts"), "utf8")).toBe(fs.readFileSync(path.join(second, "overlay_plugins.generated.ts"), "utf8"))
		expect(fs.readFileSync(path.join(first, "overlay_widgets.generated.json"), "utf8")).toBe(fs.readFileSync(path.join(second, "overlay_widgets.generated.json"), "utf8"))
	})
})
