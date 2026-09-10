import path from "node:path"
import { fileURLToPath } from "node:url"
import { generateRegistry } from "../../libs/showrunner-overlay-build/src/index.mjs"

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..")
generateRegistry({
	pluginsRoot: path.join(root, "plugins"),
	outputDirectory: path.join(root, "packages/showrunner-obs-overlay/src/generated"),
	flutterManifestOutput: path.join(root, "packages/showrunner-flutter/assets/overlay_widgets.generated.json"),
	flutterCatalogLibraryOutput: path.join(root, "packages/showrunner-flutter/lib/plugins/overlays/overlay_widget_catalog.generated.dart"),
	coreContractsOutput: path.join(root, "libs/showrunner-overlay-core/src/generated/overlay-contracts.generated.ts"),
})
