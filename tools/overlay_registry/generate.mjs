import { spawnSync } from "node:child_process"
import path from "node:path"
import { fileURLToPath } from "node:url"
import { generateRegistry } from "../../libs/showrunner-overlay-build/src/index.mjs"

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..")
const flutterCatalogLibraryOutput = path.join(root, "packages/showrunner-flutter/lib/plugins/overlays/overlay_widget_catalog.generated.dart")
generateRegistry({
	pluginsRoot: path.join(root, "plugins"),
	outputDirectory: path.join(root, "packages/showrunner-obs-overlay/src/generated"),
	flutterManifestOutput: path.join(root, "packages/showrunner-flutter/assets/overlay_widgets.generated.json"),
	flutterCatalogLibraryOutput,
	coreContractsOutput: path.join(root, "libs/showrunner-overlay-core/src/generated/overlay-contracts.generated.ts"),
})

// The browser-only CI job does not install Flutter, but the Windows Flutter
// and release jobs do. Format the generated Dart catalog whenever the SDK is
// available so `overlay:generate` is clean in the environments that compile
// the desktop application.
const dartCommand = process.platform === "win32" ? "dart.bat" : "dart"
const result = spawnSync(dartCommand, ["format", flutterCatalogLibraryOutput], {
	stdio: "inherit",
	shell: process.platform === "win32",
})
if (result.error && result.error.code !== "ENOENT") throw result.error
if (result.status !== null && result.status !== 0) process.exit(result.status)
